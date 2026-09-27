import Foundation

final class EbookPlayerSheetModel: EbookPlayerSheet.Model {
  override func onCatchUpTapped() {
    isPresented = false
    player.onPositionSyncOfferAccepted()
  }
}
