import SwiftUI

extension View {
  func queueChoiceDialog(
    _ choice: Binding<QueueChoice?>,
    onSelect: @escaping (QueueChoice, QueueChoice.Scope) -> Void
  ) -> some View {
    confirmationDialog(
      "Some items are already finished",
      isPresented: Binding(
        get: { choice.wrappedValue != nil },
        set: { if !$0 { choice.wrappedValue = nil } }
      ),
      titleVisibility: .visible,
      presenting: choice.wrappedValue
    ) { choice in
      switch choice.action {
      case .play:
        Button("Play Unfinished (\(choice.unfinishedCount))") { onSelect(choice, .unfinished) }
        Button("Play All (\(choice.totalCount))") { onSelect(choice, .all) }
      case .addToQueue:
        Button("Queue Unfinished (\(choice.unfinishedCount))") { onSelect(choice, .unfinished) }
        Button("Queue All (\(choice.totalCount))") { onSelect(choice, .all) }
      }
      Button("Cancel", role: .cancel) {}
    }
  }
}
