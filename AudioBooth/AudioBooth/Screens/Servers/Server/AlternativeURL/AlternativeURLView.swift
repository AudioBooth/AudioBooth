import Combine
import SwiftUI

struct AlternativeURLView: View {
  @StateObject var model: Model

  var body: some View {
    Form {
      Section {
        HStack {
          TextField("https://...", text: $model.url)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)

          if !model.url.isEmpty {
            Button(action: model.onClearURL) {
              Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
          }
        }

        if let error = model.error {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
        }
      } footer: {
        Text("An alternative URL to use when connecting from a different network (e.g. when at home).")
      }

      if model.hasUnsavedChanges {
        Section {
          Button(action: model.onSaveURL) {
            HStack {
              if model.isValidating {
                ProgressView()
                  .scaleEffect(0.8)
              }
              Text("Verify & Save")
            }
          }
          .disabled(model.isValidating)
        }
      }
    }
    .navigationTitle("Alternative URL")
    .navigationBarTitleDisplayMode(.inline)
  }
}

extension AlternativeURLView {
  @Observable
  class Model: ObservableObject {
    var url: String
    var savedURL: String
    var isValidating: Bool
    var error: String?

    var hasUnsavedChanges: Bool {
      url.trimmingCharacters(in: .whitespacesAndNewlines) != savedURL
        && !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func onSaveURL() {}
    func onClearURL() {}

    init(url: String = "", isValidating: Bool = false, error: String? = nil) {
      self.url = url
      self.savedURL = url
      self.isValidating = isValidating
      self.error = error
    }
  }
}

extension AlternativeURLView.Model {
  static let mock = AlternativeURLView.Model()
}

#Preview("Empty") {
  NavigationStack {
    AlternativeURLView(model: .init())
  }
}

#Preview("Saved") {
  NavigationStack {
    AlternativeURLView(model: .init(url: "https://abs.example.com"))
  }
}
