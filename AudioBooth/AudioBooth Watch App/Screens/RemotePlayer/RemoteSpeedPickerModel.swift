import Foundation

final class RemoteSpeedPickerModel: SpeedPickerSheet.Model {
  private let connectivityManager = WatchConnectivityManager.shared

  init() {
    super.init(speed: WatchConnectivityManager.shared.playbackRate)
  }

  override func onSpeedChanged(_ speed: Float) {
    self.speed = speed
    connectivityManager.playbackRate = speed
    connectivityManager.changePlaybackRate(speed)
  }
}
