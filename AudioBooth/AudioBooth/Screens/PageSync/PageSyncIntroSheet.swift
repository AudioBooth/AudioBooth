import Combine
import SwiftUI

/// One-time explanation of Page Sync, shown before the first scan.
struct PageSyncIntroSheet: View {
  @ObservedObject var model: Model
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: 28) {
      Spacer()

      HStack(spacing: 16) {
        Image(systemName: "book.closed.fill")
        Image(systemName: "arrow.right")
          .font(.title2)
          .foregroundStyle(.secondary)
        Image(systemName: "headphones")
      }
      .font(.system(size: 44))
      .foregroundStyle(.tint)

      VStack(spacing: 12) {
        Text("Page Sync")
          .font(.title2)
          .fontWeight(.semibold)

        Text("Pick up the audiobook right where you are in the printed book.")
          .multilineTextAlignment(.center)
      }

      VStack(alignment: .leading, spacing: 14) {
        row("camera.viewfinder", "Point the camera at the page you are reading. It captures on its own.")
        row("text.book.closed", "AudioBooth finds that page in the ebook edition from your library.")
        row(
          "waveform",
          "Then it listens to the audiobook around that spot to land on the exact sentence. Everything runs on your device."
        )
      }
      .font(.subheadline)
      .padding(.horizontal, 8)

      Text(
        "It needs the ebook edition of the title in your Audiobookshelf library. It can be a separate item with the same title."
      )
      .font(.footnote)
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)

      Spacer()

      Button(action: {
        model.onContinue()
        dismiss()
      }) {
        Text("Got it")
          .frame(maxWidth: .infinity)
          .padding(.vertical, 8)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
    }
    .padding(24)
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
  }

  private func row(_ systemImage: String, _ text: LocalizedStringResource) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: systemImage)
        .frame(width: 24)
        .foregroundStyle(.tint)
      Text(text)
    }
  }
}

extension PageSyncIntroSheet {
  @Observable
  class Model: ObservableObject, Identifiable {
    let id = UUID()
    let onContinue: () -> Void

    init(onContinue: @escaping () -> Void) {
      self.onContinue = onContinue
    }
  }
}

enum PageSyncIntro {
  private static let shownKey = "pageSyncIntroShown"

  static var wasShown: Bool {
    UserDefaults.standard.bool(forKey: shownKey)
  }

  /// Runs `action` right away if the intro was already seen; otherwise hands a sheet model to
  /// `present` whose "Got it" runs the action.
  static func gate(_ action: @escaping () -> Void, present: (PageSyncIntroSheet.Model) -> Void) {
    if wasShown {
      action()
      return
    }
    present(
      PageSyncIntroSheet.Model {
        UserDefaults.standard.set(true, forKey: shownKey)
        action()
      }
    )
  }
}

#Preview {
  PageSyncIntroSheet(model: PageSyncIntroSheet.Model(onContinue: {}))
}
