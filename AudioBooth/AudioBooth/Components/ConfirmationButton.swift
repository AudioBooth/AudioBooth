import SwiftUI

struct ConfirmationButton<Label: View>: View {
  struct Confirmation {
    let title: String
    let message: String?
    let action: String

    init(title: String, message: String? = nil, action: String? = nil) {
      self.title = title
      self.message = message
      self.action = action ?? title
    }
  }

  let role: ButtonRole?
  let confirmation: Confirmation
  let action: () -> Void
  @ViewBuilder let label: () -> Label

  @State private var isPresented = false

  init(
    role: ButtonRole? = nil,
    confirmation: Confirmation,
    action: @escaping () -> Void,
    @ViewBuilder label: @escaping () -> Label
  ) {
    self.role = role
    self.confirmation = confirmation
    self.action = action
    self.label = label
  }

  var body: some View {
    Button(role: role, action: { isPresented = true }, label: label)
      .confirmationDialog(confirmation.title, isPresented: $isPresented, titleVisibility: .visible) {
        Button(confirmation.action, role: .destructive, action: action)
        Button("Cancel", role: .cancel) {}
      } message: {
        if let message = confirmation.message { Text(message) }
      }
  }
}
