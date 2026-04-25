import Combine
import SwiftUI

struct SectionDetailView: View {
  @ObservedObject var model: Model

  var body: some View {
    Group {
      switch model.state {
      case .loading:
        ProgressView()
      case .error(let message):
        VStack(spacing: 8) {
          Text(message)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
          Button("Retry") {
            Task { await model.onLoad() }
          }
          .buttonStyle(.bordered)
        }
        .padding()
      case .loaded:
        ScrollView {
          VStack(alignment: .leading, spacing: 8) {
            ForEach(model.rows) { rowModel in
              ContinueListeningRow(model: rowModel)
            }
          }
        }
      }
    }
    .navigationTitle(model.title)
    .task { await model.onLoad() }
  }
}

extension SectionDetailView {
  enum LoadState {
    case loading
    case loaded
    case error(String)
  }

  @Observable
  class Model: ObservableObject, Identifiable {
    let id: String
    var title: String
    var rows: [ContinueListeningRow.Model] = []
    var state: LoadState = .loading

    func onLoad() async {}

    init(sectionID: String, title: String) {
      self.id = sectionID
      self.title = title
    }
  }
}

#Preview {
  NavigationStack {
    SectionDetailView(
      model: SectionDetailView.Model(sectionID: "discover", title: "Discover")
    )
  }
}
