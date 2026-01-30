import AVKit

extension AVAudioSession {
  var isCarPlayConnected: Bool {
    currentRoute.outputs.contains { output in
      output.portType == AVAudioSession.Port.carAudio
    }
  }
}
