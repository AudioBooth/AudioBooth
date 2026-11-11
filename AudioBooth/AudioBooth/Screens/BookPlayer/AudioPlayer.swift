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
  private var coverURL: URL?
  private var tracks: [Track] = []
  private(set) var currentTrackIndex: Int = 0
  private var lastQueuedIndex: Int = -1
  private var timeObserver: Any?
  private var cancellables = Set<AnyCancellable>()
  private var itemObservers = Set<AnyCancellable>()
  private var wantsPlayback = false
  private var decodeRetryCount = 0
  private var decodeRetryTime: TimeInterval?
  private var pendingSeekTarget: TimeInterval?
  private var resumeTask: Task<Void, Never>?

  let events = PassthroughSubject<Event, Never>()

  var onRequireRemoteSession: ((@escaping (PlaybackSession?) -> Void) -> Void)?
  var onCastSessionEnded: (() -> Void)?

  var isCasting: Bool {
    #if canImport(GoogleCast) && !os(watchOS)
    return CastManager.shared.isConnected
    #else
    return false
    #endif
  }

  var time: TimeInterval {
    #if canImport(GoogleCast) && !os(watchOS)
    if CastManager.shared.isConnected {
      if tracks.indices.contains(currentTrackIndex) {
        let track = tracks[currentTrackIndex]
        return track.startOffset + CastManager.shared.currentPosition
      }
      return mediaProgress.currentTime
    }
    #endif
    let seconds = player.currentSeconds
    guard seconds >= 0 else { return mediaProgress.currentTime }
    guard !tracks.isEmpty else { return seconds }
    let track = tracks[currentTrackIndex]
    return track.startOffset + min(seconds, track.duration)
  }

  var isPlaying: Bool {
    #if canImport(GoogleCast) && !os(watchOS)
    if CastManager.shared.isConnected {
      return CastManager.shared.isPlaying
    }
    #endif
    return player.timeControlStatus == .playing
  }

  var isPlaybackActive: Bool {
    #if canImport(GoogleCast) && !os(watchOS)
    if CastManager.shared.isConnected {
      return CastManager.shared.isPlaying
    }
    #endif
    return player.timeControlStatus != .paused
  }

  func isPositioned(at target: TimeInterval) -> Bool {
    if let pendingSeekTarget {
      return abs(pendingSeekTarget - target) <= 1
    }
    #if canImport(GoogleCast) && !os(watchOS)
    if CastManager.shared.isConnected {
      return abs(time - target) <= 1
    }
    #endif
    guard player.currentItem?.status == .readyToPlay else { return false }
    return abs(time - target) <= 1
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
      #if canImport(GoogleCast) && !os(watchOS)
      if CastManager.shared.isConnected {
        CastManager.shared.setRate(newValue)
      } else if player.timeControlStatus == .playing {
        player.rate = newValue
      }
      #else
      if player.timeControlStatus == .playing {
        player.rate = newValue
      }
      #endif
      events.send(.rateChanged(newValue))
    }
  }

  init(mediaProgress: MediaProgress, session: PlaybackSession, coverURL: URL? = nil) {
    self.mediaProgress = mediaProgress
    self.session = session
    self.coverURL = coverURL
    player.allowsExternalPlayback = false
    player.automaticallyWaitsToMinimizeStalling = false
    setupObservers()
    #if canImport(GoogleCast) && !os(watchOS)
    setupCastCallbacks()
    #endif
  }

  deinit {
    removeTimeObserver()
    #if canImport(GoogleCast) && !os(watchOS)
    detachCastCallbacks()
    #endif
  }

  func setQueue(for session: PlaybackSession, autoPlay: Bool? = nil) {
    let wasPlaying = isPlaying
    let shouldAutoPlay = autoPlay ?? wasPlaying
    wantsPlayback = shouldAutoPlay
    pendingSeekTarget = nil
    resetDecodeRetry()
    self.session = session
    self.tracks = session.tracks.filter { url(for: $0) != nil }

    guard !self.tracks.isEmpty else {
      player.removeAllItems()
      return
    }

    AppLogger.player.info("Playing from \(self.isUsingRemoteURLs ? "remote" : "local") files")

    addTimeObserver()

    let (trackIndex, offset) = trackAndOffset(for: mediaProgress.currentTime)
    currentTrackIndex = trackIndex
    #if canImport(GoogleCast) && !os(watchOS)
    if CastManager.shared.isConnected {
      player.removeAllItems()
      loadCastCurrentTrack(seekTo: offset, autoPlay: shouldAutoPlay)
      return
    }
    #endif
    loadQueue(from: trackIndex, seekTo: offset, autoPlay: shouldAutoPlay)
  }

  func pause() {
    wantsPlayback = false
    resumeTask?.cancel()
    #if canImport(GoogleCast) && !os(watchOS)
    if CastManager.shared.isConnected {
      CastManager.shared.pause()
      return
    }
    #endif
    player.pause()
  }

  func resume() {
    guard !tracks.isEmpty else {
      events.send(.error(nil))
      return
    }

    wantsPlayback = true

    #if canImport(GoogleCast) && !os(watchOS)
    if CastManager.shared.isConnected {
      player.pause()
      let (trackIndex, offset) = trackAndOffset(for: mediaProgress.currentTime)
      guard tracks.indices.contains(trackIndex) else { return }
      let track = tracks[trackIndex]
      let expectedURL = session.remoteURL(for: track) ?? session.url(for: track)

      if let expectedURL, CastManager.shared.currentStreamURL == expectedURL {
        if !CastManager.shared.isPlaying {
          CastManager.shared.play()
        } else {
          events.send(.stateChanged(.playing))
        }
      } else {
        currentTrackIndex = trackIndex
        loadCastCurrentTrack(seekTo: offset, autoPlay: true)
      }
      return
    }
    #endif

    AudioSession.configure()

    resumeTask?.cancel()
    resumeTask = Task {
      let activated = await AudioSession.activate()

      guard !Task.isCancelled, wantsPlayback else {
        events.send(.stateChanged(isPlaying ? .playing : .paused))
        return
      }

      if isPlaying {
        events.send(.stateChanged(.playing))
      } else if player.currentItem == nil || player.currentItem?.status == .failed {
        let (trackIndex, offset) = trackAndOffset(for: mediaProgress.currentTime)
        currentTrackIndex = trackIndex
        loadQueue(from: trackIndex, seekTo: offset, autoPlay: true)
      } else {
        if pendingSeekTarget != mediaProgress.currentTime {
          seek(to: mediaProgress.currentTime)
        }
        player.play()

        if !activated {
          events.send(.stateChanged(isPlaying ? .playing : .paused))
        }
      }
    }
  }

  func stop() {
    wantsPlayback = false
    resumeTask?.cancel()
    pendingSeekTarget = nil
    removeTimeObserver()
    #if canImport(GoogleCast) && !os(watchOS)
    if CastManager.shared.isConnected {
      CastManager.shared.pause()
      detachCastCallbacks()
    }
    #endif
    player.pause()
    player.removeAllItems()
    AudioSession.deactivate()
    events.send(.stateChanged(.stopped))
  }

  func seek(to time: TimeInterval) {
    mediaProgress.currentTime = time
    pendingSeekTarget = time

    #if canImport(GoogleCast) && !os(watchOS)
    if CastManager.shared.isConnected {
      let (targetIndex, offset) = trackAndOffset(for: time)
      if targetIndex == currentTrackIndex {
        CastManager.shared.seek(to: offset)
        pendingSeekTarget = nil
      } else {
        currentTrackIndex = targetIndex
        loadCastCurrentTrack(seekTo: offset, autoPlay: isPlaying)
      }
      events.send(.seek(time))
      return
    }
    #endif

    guard !tracks.isEmpty else {
      player.seek(
        to: CMTime(seconds: time, preferredTimescale: 1000),
        toleranceBefore: .zero,
        toleranceAfter: .zero
      ) { [weak self] _ in
        if self?.pendingSeekTarget == time {
          self?.pendingSeekTarget = nil
        }
        self?.events.send(.seek(time))
      }
      return
    }

    let (targetIndex, offset) = trackAndOffset(for: time)

    if targetIndex == currentTrackIndex, !player.items().isEmpty {
      player.seek(
        to: CMTime(seconds: offset, preferredTimescale: 1000),
        toleranceBefore: .zero,
        toleranceAfter: .zero
      ) { [weak self] _ in
        if self?.pendingSeekTarget == time {
          self?.pendingSeekTarget = nil
        }
        self?.events.send(.seek(time))
      }
      return
    }

    guard tracks.indices.contains(targetIndex) else {
      pendingSeekTarget = nil
      return
    }

    loadQueue(from: targetIndex, seekTo: offset, autoPlay: isPlaying)
    pendingSeekTarget = nil
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
      headers: Audiobookshelf.shared.authentication.server?.customHeaders,
      preciseTiming: tracks[index].codec?.lowercased() == "opus"
    )
  }

  func url(for track: Track) -> URL? {
    session.url(for: track)
  }

  func trackIndex(for item: AVPlayerItem) -> Int? {
    guard let url = (item.asset as? AVURLAsset)?.url else { return nil }
    return tracks.firstIndex { self.url(for: $0) == url }
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
  static let maxDecodeRetries = 10
  static let decodeRetryRewind: TimeInterval = 1
  static let decodeRetryStableDuration: TimeInterval = 3

  /// Works around Apple's xHE-AAC (USAC) decoder bug FB22340742, where AVPlayer reports
  /// "Cannot Decode" at certain positions and stays broken until the queue is rebuilt.
  /// Rebuilding the queue a second earlier usually gets past the bad spot.
  /// Returns true when the failure was taken over and playback was restarted.
  func recoverFromDecodeFailure(_ error: Error?) -> Bool {
    guard let error = error as? NSError,
      error.domain == AVFoundationErrorDomain,
      error.code == AVError.Code.decodeFailed.rawValue,
      !tracks.isEmpty
    else { return false }

    guard decodeRetryCount < Self.maxDecodeRetries else {
      AppLogger.player.error("Decode failure persists after \(Self.maxDecodeRetries) retries, giving up")
      resetDecodeRetry()
      return false
    }

    let position = player.currentSeconds > 0 ? time : mediaProgress.currentTime
    let retryTime = max(0, position - Self.decodeRetryRewind)

    decodeRetryCount += 1
    decodeRetryTime = retryTime

    AppLogger.player.warning(
      "Decode failure at \(position), retry \(decodeRetryCount)/\(Self.maxDecodeRetries) from \(retryTime)"
    )

    let (trackIndex, offset) = trackAndOffset(for: retryTime)
    loadQueue(from: trackIndex, seekTo: offset, autoPlay: wantsPlayback)
    mediaProgress.currentTime = retryTime

    return true
  }

  func resetDecodeRetryIfStable() {
    guard let decodeRetryTime, time > decodeRetryTime + Self.decodeRetryStableDuration else { return }
    resetDecodeRetry()
  }

  func resetDecodeRetry() {
    decodeRetryCount = 0
    decodeRetryTime = nil
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
    if let index = trackIndex(for: item) {
      currentTrackIndex = index
    }
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
          guard !self.recoverFromDecodeFailure(item.error) else { return }
          self.player.pause()
          self.player.removeAllItems()
          self.events.send(.error(item.error))
        default:
          break
        }
      }
      .store(in: &itemObservers)

    NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
      .sink { [weak self] _ in
        guard let self else { return }
        let remainingItems = self.player.items()
        if remainingItems.isEmpty || remainingItems == [item] {
          self.events.send(.finished)
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
        guard let self else { return }
        let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
        AppLogger.player.error("Failed to play to end: \(error?.localizedDescription ?? "Unknown")")
        guard !self.recoverFromDecodeFailure(error) else { return }
        self.events.send(.stalled)
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
      self.resetDecodeRetryIfStable()
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
    static let bandFrequencies: [Float] = [60, 150, 400, 1000, 2400, 6000, 15000]

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
  convenience init(url: URL, headers: [String: String]?, preciseTiming: Bool) {
    var options: [String: Any] = [AVURLAssetPreferPreciseDurationAndTimingKey: preciseTiming]
    if !url.isFileURL, let headers, !headers.isEmpty {
      options["AVURLAssetHTTPHeaderFieldsKey"] = headers
    }
    self.init(asset: AVURLAsset(url: url, options: options))
  }
}

#if canImport(GoogleCast) && !os(watchOS)
private extension AudioPlayer {
  func setupCastCallbacks() {
    CastManager.shared.onSessionStarted = { [weak self] in
      guard let self else { return }
      self.player.pause()
      let (trackIndex, offset) = self.trackAndOffset(for: self.mediaProgress.currentTime)
      self.currentTrackIndex = trackIndex
      self.loadCastCurrentTrack(seekTo: offset, autoPlay: self.wantsPlayback || self.isPlaying)
    }

    CastManager.shared.onPositionUpdate = { [weak self] trackPosition in
      guard let self else { return }
      guard self.tracks.indices.contains(self.currentTrackIndex) else { return }
      let globalTime = self.tracks[self.currentTrackIndex].startOffset + trackPosition
      if let target = self.pendingSeekTarget {
        if abs(globalTime - target) <= 2 {
          self.pendingSeekTarget = nil
        } else {
          return
        }
      }
      self.mediaProgress.currentTime = globalTime
      self.events.send(.timeUpdate(globalTime))
    }

    CastManager.shared.onStateChange = { [weak self] isPlaying in
      guard let self else { return }
      if isPlaying {
        self.pendingSeekTarget = nil
      }
      self.events.send(.stateChanged(isPlaying ? .playing : .paused))
    }

    CastManager.shared.onTrackFinished = { [weak self] in
      guard let self else { return }
      let nextIndex = self.currentTrackIndex + 1
      if self.tracks.indices.contains(nextIndex) {
        self.currentTrackIndex = nextIndex
        self.mediaProgress.currentTime = self.tracks[nextIndex].startOffset
        self.loadCastCurrentTrack(seekTo: 0, autoPlay: true)
      } else {
        if self.mediaProgress.duration > 0 {
          self.mediaProgress.currentTime = self.mediaProgress.duration
        }
        self.events.send(.finished)
        CastManager.shared.disconnect()
      }
    }

    CastManager.shared.onError = { [weak self] in
      guard let self else { return }
      self.events.send(.error(nil))
    }

    CastManager.shared.onSessionEnded = { [weak self] in
      guard let self else { return }
      self.events.send(.stateChanged(.paused))
      if let onCastSessionEnded = self.onCastSessionEnded {
        onCastSessionEnded()
      } else {
        self.seek(to: self.mediaProgress.currentTime)
      }
    }
  }

  func detachCastCallbacks() {
    CastManager.shared.onSessionStarted = nil
    CastManager.shared.onPositionUpdate = nil
    CastManager.shared.onStateChange = nil
    CastManager.shared.onTrackFinished = nil
    CastManager.shared.onError = nil
    CastManager.shared.onSessionEnded = nil
  }

  func loadCastCurrentTrack(seekTo offset: TimeInterval? = nil, autoPlay: Bool = true) {
    guard tracks.indices.contains(currentTrackIndex) else { return }
    let track = tracks[currentTrackIndex]

    if session.remoteURL(for: track) == nil {
      onRequireRemoteSession? { [weak self] newSession in
        guard let self else { return }
        guard let newSession, self.tracks.indices.contains(self.currentTrackIndex),
          newSession.remoteURL(for: self.tracks[self.currentTrackIndex]) != nil
        else {
          self.events.send(.error(nil))
          return
        }
        self.session = newSession
        self.tracks = newSession.tracks
        self.loadCastCurrentTrack(seekTo: offset, autoPlay: autoPlay)
      }
      return
    }

    guard let streamURL = session.remoteURL(for: track) ?? session.url(for: track) else { return }

    let startOffset = offset ?? max(0, mediaProgress.currentTime - track.startOffset)
    CastManager.shared.load(
      streamURL: streamURL,
      title: session.displayTitle ?? "Audiobook",
      author: session.displayAuthor,
      coverURL: coverURL,
      startTime: startOffset,
      playbackRate: rate > 0 ? rate : 1.0,
      contentType: track.mimeType ?? "audio/mpeg",
      autoplay: autoPlay
    )
  }
}
#endif
