import Combine

final class OnboardingViewModel: OnboardingView.Model {
  override func onConnectTapped() {
    serverModel = ServerViewModel()
  }

  override func onNoServerTapped() {
    infoModel = AudiobookshelfInfoView.Model()
  }
}
