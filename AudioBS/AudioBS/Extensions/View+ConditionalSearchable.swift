import SwiftUI

extension View {
  @ViewBuilder
  func conditionalSearchable(text: Binding<String>, prompt: String) -> some View {
    if #available(iOS 26.0, *) {
      self
    } else {
      self.searchable(text: text, prompt: prompt)
    }
  }
}
