import AVFoundation
import Combine
import CoreAudio
import Logging
import MediaToolbox
import Models

final class AudioPlayer {
  enum PlaybackState {
    case playing
    case paused
    case stopped
    case buffering
    case ready
    case error
  }

  enum Event {
    case timeUpdate(TimeInterval)
    case stateChanged(PlaybackState)
    case seek(TimeInterval)
    case rateChanged(Float)
    case finished
    case stalled
    case error(Error?)
  }

  private let player = AVPlayer()
  private let eqContext = EQContext()
  private let mediaProgress: MediaProgress
  private var tracks: [Track] = []
  private var trackURLs: [URL] = []
  private(set) var currentTrackIndex: Int = 0
  private var isPrepared: Bool = false
  private var timeObserver: Any?
  private var cancellables = Set<AnyCancellable>()
  private var itemObservers = Set<AnyCancellable>()

  let events = PassthroughSubject<Event, Never>()

  var time: TimeInterval {
    if isPrepared { return mediaProgress.currentTime }
    guard !tracks.isEmpty else { return player.currentSeconds }
    return tracks[currentTrackIndex].startOffset + player.currentSeconds
  }

  var duration: TimeInterval {
    let d = player.currentItem?.duration.seconds ?? 0
    return d.isNaN ? 0 : d
  }

  var isPlaying: Bool {
    player.timeControlStatus == .playing
  }

  var isBuffering: Bool {
    player.timeControlStatus == .waitingToPlayAtSpecifiedRate
  }

  var hasContent: Bool {
    !trackURLs.isEmpty
  }

  var volume: Float {
    get { player.volume }
    set { player.volume = newValue }
  }

  var rate: Float {
    get { player.defaultRate }
    set {
      player.defaultRate = newValue
      if player.timeControlStatus == .playing {
        player.rate = newValue
      }
      events.send(.rateChanged(newValue))
    }
  }

  init(mediaProgress: MediaProgress) {
    self.mediaProgress = mediaProgress
    player.allowsExternalPlayback = false
    setupObservers()
  }

  deinit {
    removeTimeObserver()
  }

  func prepare(
    tracks: [Track],
    urlResolver: (Track) -> URL?
  ) {
    var resolvedTracks: [Track] = []
    var urls: [URL] = []
    for track in tracks {
      guard let url = urlResolver(track) else { continue }
      resolvedTracks.append(track)
      urls.append(url)
    }
    self.tracks = resolvedTracks
    self.trackURLs = urls
    self.isPrepared = !urls.isEmpty

    addTimeObserver()
  }

  func pause() {
    player.pause()
  }

  func resume() {
    if isPrepared {
      isPrepared = false
      guard !trackURLs.isEmpty else {
        events.send(.error(nil))
        return
      }

      let (trackIndex, offset) = trackAndOffset(for: mediaProgress.currentTime)
      currentTrackIndex = trackIndex
      loadTrack(at: trackIndex, seekTo: offset, autoPlay: true)
    } else if player.currentItem != nil, player.currentItem?.status != .failed {
      player.play()
    } else {
      let (trackIndex, offset) = trackAndOffset(for: mediaProgress.currentTime)
      currentTrackIndex = trackIndex
      loadTrack(at: trackIndex, seekTo: offset, autoPlay: true)
    }
  }

  func stop() {
    removeTimeObserver()
    player.pause()
    player.replaceCurrentItem(with: nil)
    events.send(.stateChanged(.stopped))
  }

  func seek(to time: TimeInterval) {
    if isPrepared {
      events.send(.timeUpdate(time))
      events.send(.seek(time))
      return
    }

    guard !tracks.isEmpty else {
      player.seek(to: CMTime(seconds: time, preferredTimescale: 1000)) { [weak self] _ in
        self?.events.send(.seek(time))
      }
      return
    }

    let (targetIndex, offset) = trackAndOffset(for: time)

    if targetIndex == currentTrackIndex {
      player.seek(to: CMTime(seconds: offset, preferredTimescale: 1000)) { [weak self] _ in
        self?.events.send(.seek(time))
      }
      return
    }

    currentTrackIndex = targetIndex
    guard targetIndex < trackURLs.count else { return }
    loadTrack(at: targetIndex, seekTo: offset, autoPlay: isPlaying)
    events.send(.seek(time))
  }

  func rebuildQueue(urlResolver: (Track) -> URL?) {
    let currentGlobal = time
    let wasPlaying = isPlaying

    var resolvedTracks: [Track] = []
    var urls: [URL] = []
    for track in tracks {
      guard let url = urlResolver(track) else { continue }
      resolvedTracks.append(track)
      urls.append(url)
    }
    self.tracks = resolvedTracks
    self.trackURLs = urls

    guard !urls.isEmpty else { return }

    let (trackIndex, offset) = trackAndOffset(for: currentGlobal)
    currentTrackIndex = trackIndex
    loadTrack(at: trackIndex, seekTo: offset, autoPlay: wasPlaying)
  }
}

private extension AudioPlayer {
  func loadTrack(at index: Int, seekTo offset: TimeInterval, autoPlay: Bool) {
    guard index < trackURLs.count else { return }

    let item = AVPlayerItem(url: trackURLs[index])
    observeItem(item)
    applyEQ(to: item)
    player.replaceCurrentItem(with: item)

    if offset > 0 {
      player.seek(to: CMTime(seconds: offset, preferredTimescale: 1000)) { [weak self] _ in
        guard let self, autoPlay else { return }
        self.player.play()
        self.player.rate = self.player.defaultRate
      }
    } else if autoPlay {
      player.play()
      player.rate = player.defaultRate
    }
  }

  func advanceToNextTrack() {
    guard currentTrackIndex < tracks.count - 1 else {
      events.send(.finished)
      return
    }

    currentTrackIndex += 1
    AppLogger.player.debug("Advanced to track \(self.currentTrackIndex)/\(self.tracks.count)")
    loadTrack(at: currentTrackIndex, seekTo: 0, autoPlay: true)
  }

  func trackAndOffset(for time: TimeInterval) -> (Int, TimeInterval) {
    guard !tracks.isEmpty else { return (0, time) }

    let totalDuration = tracks.reduce(0) { $0 + $1.duration }
    let clampedTime = max(0, min(time, totalDuration))

    for (i, track) in tracks.enumerated() {
      let trackEnd = track.startOffset + track.duration
      if clampedTime < trackEnd || i == tracks.count - 1 {
        return (i, clampedTime - track.startOffset)
      }
    }

    return (0, 0)
  }
}

private extension AudioPlayer {
  func setupObservers() {
    player.publisher(for: \.timeControlStatus)
      .removeDuplicates()
      .sink { [weak self] status in
        guard let self else { return }
        switch status {
        case .paused:
          self.events.send(.stateChanged(.paused))
        case .playing:
          self.events.send(.stateChanged(.playing))
        case .waitingToPlayAtSpecifiedRate where player.status != .readyToPlay:
          self.events.send(.stateChanged(.buffering))
        default:
          break
        }
      }
      .store(in: &cancellables)
  }

  func observeItem(_ item: AVPlayerItem) {
    itemObservers.removeAll()

    item.publisher(for: \.status)
      .removeDuplicates()
      .sink { [weak self] status in
        guard let self else { return }
        switch status {
        case .readyToPlay:
          self.events.send(.stateChanged(.ready))
        case .failed:
          AppLogger.player.error("Player item failed: \(item.error?.localizedDescription ?? "Unknown")")
          self.events.send(.error(item.error))
        default:
          break
        }
      }
      .store(in: &itemObservers)

    NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
      .sink { [weak self] _ in
        self?.advanceToNextTrack()
      }
      .store(in: &itemObservers)

    NotificationCenter.default.publisher(for: AVPlayerItem.playbackStalledNotification, object: item)
      .sink { [weak self] _ in
        AppLogger.player.warning("Playback stalled")
        self?.events.send(.stalled)
      }
      .store(in: &itemObservers)

    NotificationCenter.default.publisher(for: AVPlayerItem.failedToPlayToEndTimeNotification, object: item)
      .sink { [weak self] notification in
        let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
        AppLogger.player.error("Failed to play to end: \(error?.localizedDescription ?? "Unknown")")
        self?.events.send(.stalled)
      }
      .store(in: &itemObservers)

    NotificationCenter.default.publisher(for: AVPlayerItem.newErrorLogEntryNotification, object: item)
      .sink { _ in
        guard let entry = item.errorLog()?.events.last else { return }
        AppLogger.player.error("Player error log: \(entry.errorStatusCode) - \(entry.errorComment ?? "")")
      }
      .store(in: &itemObservers)
  }

  func addTimeObserver() {
    removeTimeObserver()
    let interval = CMTime(seconds: 0.5, preferredTimescale: 1000)
    timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
      guard let self, !self.isPrepared else { return }
      self.events.send(.timeUpdate(self.time))
    }
  }

  func removeTimeObserver() {
    if let observer = timeObserver {
      player.removeTimeObserver(observer)
      timeObserver = nil
    }
  }
}

private extension AVPlayer {
  var currentSeconds: TimeInterval {
    currentTime().seconds.isNaN ? 0 : currentTime().seconds
  }
}

extension AudioPlayer {
  func setEQPreamp(_ value: Float) {
    eqContext.setPreamp(value)
  }

  func setEQBand(_ index: Int, gain: Float) {
    eqContext.setBandGain(index, gain: gain)
  }

  var isEQEnabled: Bool {
    get { eqContext.isEnabled }
    set { eqContext.isEnabled = newValue }
  }

  var eqBands: [Float] {
    eqContext.bandGains
  }

  final class EQContext {
    static let bandFrequencies: [Float] = [60, 150, 400, 1000, 2400, 15000]

    private(set) var engine: AVAudioEngine?
    private(set) var eq: AVAudioUnitEQ?
    private var sourceNode: AVAudioSourceNode?
    private var outputBuffer: AVAudioPCMBuffer?
    private var inputBufferList: UnsafeMutablePointer<AudioBufferList>?
    var isEnabled = false
    var preamp: Float = 0
    var bandGains: [Float]

    init() {
      bandGains = [Float](repeating: 0, count: Self.bandFrequencies.count)
    }

    func prepare(format: AVAudioFormat, maxFrames: AVAudioFrameCount) {
      unprepare()

      let newEngine = AVAudioEngine()
      let newEQ = AVAudioUnitEQ(numberOfBands: Self.bandFrequencies.count)

      newEQ.globalGain = preamp
      for (i, freq) in Self.bandFrequencies.enumerated() {
        let band = newEQ.bands[i]
        band.filterType = .parametric
        band.frequency = freq
        band.bandwidth = 1.0
        band.gain = bandGains[i]
        band.bypass = false
      }

      let srcNode = AVAudioSourceNode(format: format) { [weak self] _, _, _, audioBufferList in
        guard let self, let input = self.inputBufferList else { return noErr }
        let dst = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let src = UnsafeMutableAudioBufferListPointer(input)
        for i in 0..<min(dst.count, src.count) {
          if let dstData = dst[i].mData, let srcData = src[i].mData {
            memcpy(dstData, srcData, Int(min(dst[i].mDataByteSize, src[i].mDataByteSize)))
          }
        }
        return noErr
      }

      newEngine.attach(srcNode)
      newEngine.attach(newEQ)
      newEngine.connect(srcNode, to: newEQ, format: format)
      newEngine.connect(newEQ, to: newEngine.mainMixerNode, format: format)

      do {
        try newEngine.enableManualRenderingMode(.realtime, format: format, maximumFrameCount: maxFrames)
        try newEngine.start()
        outputBuffer = AVAudioPCMBuffer(pcmFormat: newEngine.manualRenderingFormat, frameCapacity: maxFrames)
        self.engine = newEngine
        self.eq = newEQ
        self.sourceNode = srcNode
      } catch {
        AppLogger.player.error("EQ engine setup failed: \(error)")
      }
    }

    func process(numberFrames: CMItemCount, bufferListInOut: UnsafeMutablePointer<AudioBufferList>) {
      guard isEnabled, let outputBuffer else { return }

      inputBufferList = bufferListInOut

      let frameCount = AVAudioFrameCount(numberFrames)
      outputBuffer.frameLength = frameCount

      var err: OSStatus = noErr
      let status = engine?.manualRenderingBlock(frameCount, outputBuffer.mutableAudioBufferList, &err)

      guard status == .success else { return }

      let src = UnsafeMutableAudioBufferListPointer(outputBuffer.mutableAudioBufferList)
      let dst = UnsafeMutableAudioBufferListPointer(bufferListInOut)
      for i in 0..<min(dst.count, src.count) {
        if let dstData = dst[i].mData, let srcData = src[i].mData {
          memcpy(dstData, srcData, Int(src[i].mDataByteSize))
        }
      }
    }

    func unprepare() {
      engine?.stop()
      engine = nil
      eq = nil
      sourceNode = nil
      outputBuffer = nil
      inputBufferList = nil
    }

    func setPreamp(_ value: Float) {
      preamp = value
      eq?.globalGain = value
    }

    func setBandGain(_ index: Int, gain: Float) {
      guard index < bandGains.count else { return }
      bandGains[index] = gain
      eq?.bands[index].gain = gain
    }
  }

  func applyEQ(to item: AVPlayerItem) {
    Task { [weak self] in
      guard let self else { return }
      guard let track = try? await item.asset.loadTracks(withMediaType: .audio).first else { return }
      guard player.currentItem === item else { return }

      let context = eqContext
      let clientInfo = Unmanaged.passRetained(context).toOpaque()

      var callbacks = MTAudioProcessingTapCallbacks(
        version: kMTAudioProcessingTapCallbacksVersion_0,
        clientInfo: UnsafeMutableRawPointer(clientInfo)
      ) { _, clientInfo, tapStorageOut in
        tapStorageOut.pointee = clientInfo
      } finalize: { tap in
        let storage = MTAudioProcessingTapGetStorage(tap)
        Unmanaged<AudioPlayer.EQContext>.fromOpaque(storage).release()
      } prepare: { tap, maxFrames, processingFormat in
        let storage = MTAudioProcessingTapGetStorage(tap)
        let ctx = Unmanaged<AudioPlayer.EQContext>.fromOpaque(storage).takeUnretainedValue()
        guard let format = AVAudioFormat(streamDescription: processingFormat) else { return }
        ctx.prepare(format: format, maxFrames: AVAudioFrameCount(maxFrames))
      } unprepare: { tap in
        let storage = MTAudioProcessingTapGetStorage(tap)
        let ctx = Unmanaged<AudioPlayer.EQContext>.fromOpaque(storage).takeUnretainedValue()
        ctx.unprepare()
      } process: { tap, numberFrames, _, bufferListInOut, numberFramesOut, flagsOut in
        guard
          MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut)
            == noErr
        else {
          return
        }
        let storage = MTAudioProcessingTapGetStorage(tap)
        let ctx = Unmanaged<AudioPlayer.EQContext>.fromOpaque(storage).takeUnretainedValue()
        ctx.process(numberFrames: numberFrames, bufferListInOut: bufferListInOut)
      }

      var tap: MTAudioProcessingTap?
      guard
        MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PreEffects, &tap)
          == noErr
      else {
        return
      }

      let params = AVMutableAudioMixInputParameters(track: track)
      params.audioTapProcessor = tap

      let audioMix = AVMutableAudioMix()
      audioMix.inputParameters = [params]
      item.audioMix = audioMix
    }
  }
}
