import API
import AVFoundation
import AudioToolbox
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

  private let player = AVQueuePlayer()
  private let eqContext = EQContext()
  private var eqEnabled = false
  private let mediaProgress: MediaProgress
  private var session: PlaybackSession
  private var tracks: [Track] = []
  private(set) var currentTrackIndex: Int = 0
  private var lastQueuedIndex: Int = -1
  private var timeObserver: Any?
  private var cancellables = Set<AnyCancellable>()
  private var itemObservers = Set<AnyCancellable>()

  let events = PassthroughSubject<Event, Never>()

  var time: TimeInterval {
    guard !tracks.isEmpty else { return player.currentSeconds }
    let track = tracks[currentTrackIndex]
    return track.startOffset + min(player.currentSeconds, track.duration)
  }

  var isPlaying: Bool {
    player.timeControlStatus == .playing
  }

  var isUsingRemoteURLs: Bool {
    tracks.contains { url(for: $0)?.isFileURL == false }
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

  init(mediaProgress: MediaProgress, session: PlaybackSession) {
    self.mediaProgress = mediaProgress
    self.session = session
    player.allowsExternalPlayback = false
    player.automaticallyWaitsToMinimizeStalling = false
    setupObservers()
  }

  deinit {
    removeTimeObserver()
  }

  func setQueue(for session: PlaybackSession) {
    let wasPlaying = isPlaying
    self.session = session
    self.tracks = session.tracks.filter { url(for: $0) != nil }

    guard !self.tracks.isEmpty else {
      player.removeAllItems()
      return
    }

    addTimeObserver()

    let (trackIndex, offset) = trackAndOffset(for: mediaProgress.currentTime)
    currentTrackIndex = trackIndex
    loadQueue(from: trackIndex, seekTo: offset, autoPlay: wasPlaying)
  }

  func pause() {
    player.pause()
  }

  func resume() {
    guard !tracks.isEmpty else {
      events.send(.error(nil))
      return
    }

    if player.currentItem == nil || player.currentItem?.status == .failed {
      let (trackIndex, offset) = trackAndOffset(for: mediaProgress.currentTime)
      currentTrackIndex = trackIndex
      loadQueue(from: trackIndex, seekTo: offset, autoPlay: true)
    } else {
      seek(to: mediaProgress.currentTime)
      player.play()
    }
  }

  func stop() {
    removeTimeObserver()
    player.pause()
    player.removeAllItems()
    events.send(.stateChanged(.stopped))
  }

  func seek(to time: TimeInterval) {
    mediaProgress.currentTime = time

    guard !tracks.isEmpty else {
      player.seek(
        to: CMTime(seconds: time, preferredTimescale: 1000),
        toleranceBefore: .zero,
        toleranceAfter: .zero
      ) { [weak self] _ in
        self?.events.send(.seek(time))
      }
      return
    }

    let (targetIndex, offset) = trackAndOffset(for: time)

    if targetIndex == currentTrackIndex {
      player.seek(
        to: CMTime(seconds: offset, preferredTimescale: 1000),
        toleranceBefore: .zero,
        toleranceAfter: .zero
      ) { [weak self] _ in
        self?.events.send(.seek(time))
      }
      return
    }

    guard tracks.indices.contains(targetIndex) else { return }

    loadQueue(from: targetIndex, seekTo: offset, autoPlay: isPlaying)
    events.send(.seek(time))
  }

}

private extension AudioPlayer {
  static let maxQueuedItems = 3

  func loadQueue(from index: Int, seekTo offset: TimeInterval, autoPlay: Bool) {
    guard tracks.indices.contains(index) else { return }

    player.removeAllItems()
    currentTrackIndex = index
    lastQueuedIndex = index - 1
    topUpQueue()

    if offset > 0, let firstItem = player.items().first {
      firstItem.seek(
        to: CMTime(seconds: offset, preferredTimescale: 1000),
        toleranceBefore: .zero,
        toleranceAfter: .zero,
        completionHandler: nil
      )
    }

    if autoPlay {
      player.play()
      player.rate = player.defaultRate
    }
  }

  func topUpQueue() {
    while player.items().count < Self.maxQueuedItems {
      let nextIndex = lastQueuedIndex + 1
      guard tracks.indices.contains(nextIndex) else { break }
      lastQueuedIndex = nextIndex
      guard let item = makeItem(at: nextIndex) else { continue }
      player.insert(item, after: nil)
    }
    applyEQToUpcoming()
  }

  func makeItem(at index: Int) -> AVPlayerItem? {
    guard index < tracks.count, let url = url(for: tracks[index]) else { return nil }
    return AVPlayerItem(
      url: url,
      headers: Audiobookshelf.shared.authentication.server?.customHeaders
    )
  }

  func url(for track: Track) -> URL? {
    session.url(for: track)
  }

  func applyEQToUpcoming() {
    guard eqEnabled else { return }
    Task { [weak self] in await self?.attachEQ() }
  }

  private func attachEQ() async {
    for item in player.items().prefix(2) where item.audioMix == nil {
      await applyEQ(to: item)
    }
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
        case .waitingToPlayAtSpecifiedRate:
          self.events.send(.stateChanged(.buffering))
        default:
          break
        }
      }
      .store(in: &cancellables)

    player.publisher(for: \.currentItem)
      .sink { [weak self] item in
        self?.handleCurrentItemChange(item)
      }
      .store(in: &cancellables)
  }

  func handleCurrentItemChange(_ item: AVPlayerItem?) {
    guard let item else { return }
    AppLogger.player.debug("Now playing track \(self.currentTrackIndex)/\(self.tracks.count)")
    observeItem(item)
    topUpQueue()
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
        guard let self else { return }
        if self.currentTrackIndex == self.tracks.count - 1 {
          self.events.send(.finished)
        } else {
          self.currentTrackIndex += 1
        }
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
      guard let self, self.player.currentSeconds > 0 else { return }
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

  func setLevelingStrength(_ strength: LevelingStrength) {
    eqContext.setLevelingStrength(strength)
  }

  func setEQEnabled(_ enabled: Bool) {
    guard eqEnabled != enabled else { return }
    eqEnabled = enabled

    guard player.currentItem != nil else { return }

    let time = mediaProgress.currentTime
    Task { [weak self] in
      guard let self else { return }
      if enabled {
        await attachEQ()
      } else {
        for item in player.items() {
          item.audioMix = nil
        }
      }
      seek(to: time)
    }
  }

  final class EQContext {
    static let bandFrequencies: [Float] = [60, 150, 400, 1000, 2400, 15000]

    private(set) var engine: AVAudioEngine?
    private(set) var eq: AVAudioUnitEQ?
    private(set) var compressor: AVAudioUnitEffect?
    private var sourceNode: AVAudioSourceNode?
    private var outputBuffer: AVAudioPCMBuffer?
    private var inputBufferList: UnsafeMutablePointer<AudioBufferList>?
    var levelingStrength: LevelingStrength = .off {
      didSet { compressor?.bypass = levelingStrength == .off }
    }
    var preamp: Float = 0
    var bandGains: [Float]

    var eqHasEffect: Bool { preamp != 0 || bandGains.contains { $0 != 0 } }

    init() {
      bandGains = [Float](repeating: 0, count: Self.bandFrequencies.count)
    }

    func prepare(format: AVAudioFormat, maxFrames: AVAudioFrameCount) {
      unprepare()

      let newEngine = AVAudioEngine()
      let newEQ = AVAudioUnitEQ(numberOfBands: Self.bandFrequencies.count)

      newEQ.globalGain = preamp
      newEQ.bypass = !eqHasEffect
      for (i, freq) in Self.bandFrequencies.enumerated() {
        let band = newEQ.bands[i]
        band.filterType = .parametric
        band.frequency = freq
        band.bandwidth = 1.0
        band.gain = bandGains[i]
        band.bypass = false
      }

      let newCompressor = AVAudioUnitEffect(
        audioComponentDescription: AudioComponentDescription(
          componentType: kAudioUnitType_Effect,
          componentSubType: kAudioUnitSubType_DynamicsProcessor,
          componentManufacturer: kAudioUnitManufacturer_Apple,
          componentFlags: 0,
          componentFlagsMask: 0
        )
      )
      newCompressor.bypass = levelingStrength == .off

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
      newEngine.attach(newCompressor)
      newEngine.connect(srcNode, to: newEQ, format: format)
      newEngine.connect(newEQ, to: newCompressor, format: format)
      newEngine.connect(newCompressor, to: newEngine.mainMixerNode, format: format)

      do {
        try newEngine.enableManualRenderingMode(.realtime, format: format, maximumFrameCount: maxFrames)
        try newEngine.start()
        outputBuffer = AVAudioPCMBuffer(pcmFormat: newEngine.manualRenderingFormat, frameCapacity: maxFrames)
        self.engine = newEngine
        self.eq = newEQ
        self.compressor = newCompressor
        self.sourceNode = srcNode
        applyLevelingParameters()
      } catch {
        AppLogger.player.error("EQ engine setup failed: \(error)")
      }
    }

    func process(numberFrames: CMItemCount, bufferListInOut: UnsafeMutablePointer<AudioBufferList>) {
      guard let outputBuffer else { return }

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
      compressor = nil
      sourceNode = nil
      outputBuffer = nil
      inputBufferList = nil
    }

    func setPreamp(_ value: Float) {
      preamp = value
      eq?.globalGain = value
      eq?.bypass = !eqHasEffect
    }

    func setBandGain(_ index: Int, gain: Float) {
      guard index < bandGains.count else { return }
      bandGains[index] = gain
      eq?.bands[index].gain = gain
      eq?.bypass = !eqHasEffect
    }

    func setLevelingStrength(_ strength: LevelingStrength) {
      levelingStrength = strength
      applyLevelingParameters()
    }

    private func applyLevelingParameters() {
      guard let unit = compressor?.audioUnit, let params = levelingStrength.parameters else { return }
      AudioUnitSetParameter(unit, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, params.threshold, 0)
      AudioUnitSetParameter(unit, kDynamicsProcessorParam_HeadRoom, kAudioUnitScope_Global, 0, params.headroom, 0)
      AudioUnitSetParameter(unit, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, params.attack, 0)
      AudioUnitSetParameter(unit, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, params.release, 0)
      AudioUnitSetParameter(unit, kDynamicsProcessorParam_OverallGain, kAudioUnitScope_Global, 0, params.makeupGain, 0)
    }
  }

  func applyEQ(to item: AVPlayerItem) async {
    guard let track = try? await item.asset.loadTracks(withMediaType: .audio).first else { return }

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

extension LevelingStrength {
  var parameters: (threshold: Float, headroom: Float, attack: Float, release: Float, makeupGain: Float)? {
    switch self {
    case .off: nil
    case .low: (-18, 8, 0.001, 0.2, 4)
    case .medium: (-24, 6, 0.001, 0.2, 7)
    case .high: (-30, 5, 0.001, 0.2, 10)
    }
  }
}

extension AVPlayerItem {
  convenience init(url: URL, headers: [String: String]?) {
    if !url.isFileURL, let headers, !headers.isEmpty {
      let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
      self.init(asset: asset)
    } else {
      self.init(asset: AVURLAsset(url: url))
    }
  }
}
