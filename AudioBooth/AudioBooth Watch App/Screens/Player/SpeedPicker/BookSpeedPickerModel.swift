import Foundation

final class BookSpeedPickerModel: SpeedPickerSheet.Model {
  weak var playerModel: BookPlayerModel?
  weak var optionsModel: BookPlayerOptionsModel?

  private static let speedKey = "watchPlaybackSpeed"

  static var savedSpeed: Float {
    let saved = UserDefaults.standard.float(forKey: speedKey)
    return saved > 0 ? saved : WatchConnectivityManager.shared.playbackRate
  }

  init(playerModel: BookPlayerModel) {
    self.playerModel = playerModel
    super.init(speed: Self.savedSpeed)
  }

  override func onSpeedChanged(_ speed: Float) {
    self.speed = speed
    UserDefaults.standard.set(speed, forKey: Self.speedKey)
    optionsModel?.speed = speed
    playerModel?.changeSpeed(speed)
  }
}
