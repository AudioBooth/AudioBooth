import SwiftUI

extension ToolbarContent {
  @ToolbarContentBuilder
  func sharedBackgroundHidden() -> some ToolbarContent {
    if #available(iOS 26.0, *) {
      self.sharedBackgroundVisibility(.hidden)
    } else {
      self
    }
  }
}
