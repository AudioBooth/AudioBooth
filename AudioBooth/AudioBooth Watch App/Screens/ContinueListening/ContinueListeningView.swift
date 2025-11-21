import Combine
import SwiftUI

struct ContinueListeningView: View {
  @StateObject var model: Model

  var body: some View {
    Group {
      if model.continueListeningRows.isEmpty && model.availableOfflineRows.isEmpty {
        ProgressView()
      } else {
        content
      }
    }
    .navigationTitle("AudioBooth")
  }

  private var content: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        if !model.continueListeningRows.isEmpty {
          sectionHeader("Continue Listening")
          ForEach(model.continueListeningRows) { rowModel in
            ContinueListeningRow(model: rowModel)
          }
        }

        if !model.availableOfflineRows.isEmpty {
          sectionHeader("Available Offline")
          ForEach(model.availableOfflineRows) { rowModel in
            ContinueListeningRow(model: rowModel)
          }
        }
      }
    }
  }

  private func sectionHeader(_ title: String) -> some View {
    Text(title)
      .font(.caption)
      .fontWeight(.semibold)
      .foregroundStyle(.secondary)
      .textCase(.uppercase)
      .padding(.horizontal)
      .padding(.top, 8)
  }
}

extension ContinueListeningView {
  @Observable
  class Model: ObservableObject {
    var continueListeningRows: [ContinueListeningRow.Model]
    var availableOfflineRows: [ContinueListeningRow.Model]

    init(
      continueListeningRows: [ContinueListeningRow.Model] = [],
      availableOfflineRows: [ContinueListeningRow.Model] = []
    ) {
      self.continueListeningRows = continueListeningRows
      self.availableOfflineRows = availableOfflineRows
    }
  }
}

#Preview {
  NavigationStack {
    ContinueListeningView(
      model: ContinueListeningView.Model(
        continueListeningRows: [
          ContinueListeningRow.Model(
            id: "1",
            title: "The Lord of the Rings",
            author: "J.R.R. Tolkien",
            coverURL: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"),
            timeRemaining: "7 hr left"
          ),
          ContinueListeningRow.Model(
            id: "2",
            title: "Dune",
            author: "Frank Herbert",
            coverURL: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg"),
            timeRemaining: "700 hr left"
          ),
        ],
        availableOfflineRows: [
          ContinueListeningRow.Model(
            id: "3",
            title: "The Foundation",
            author: "Isaac Asimov",
            coverURL: URL(string: "https://m.media-amazon.com/images/I/51I5xPlDi9L._SL500_.jpg"),
            timeRemaining: "633 hr left"
          )
        ]
      )
    )
  }
}
