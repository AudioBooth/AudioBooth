import Combine
import SwiftUI

struct CustomHeadersView: View {
  @Environment(\.dismiss) private var dismiss

  @StateObject var model: Model

  var body: some View {
    List {
      Section {
        ForEach(model.headers) { header in
          HStack {
            VStack(alignment: .leading, spacing: 4) {
              Text(header.key)
                .font(.headline)
              Text(header.value)
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            Spacer()
          }
          .padding(.vertical, 4)
        }
        .onDelete(perform: model.onDelete)

        Button(action: model.onAddHeaderTapped) {
          HStack {
            Image(systemName: "plus.circle.fill")
            Text("Add Header")
          }
        }
      } footer: {
        Text("Custom headers will be sent with every request to your server.")
          .font(.caption)
      }
    }
    .navigationTitle("Custom Headers")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $model.showAddSheet) {
      AddHeaderView(
        headerKey: $model.newHeaderKey,
        headerValue: $model.newHeaderValue,
        onSave: model.onSaveHeader,
        onCancel: model.onCancelAdd
      )
    }
  }
}

struct AddHeaderView: View {
  @Binding var headerKey: String
  @Binding var headerValue: String
  let onSave: () -> Void
  let onCancel: () -> Void

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Header Name", text: $headerKey)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)

          TextField("Header Value", text: $headerValue)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        } header: {
          Text("Header Details")
        } footer: {
          Text("Example: X-API-Key, Authorization, etc.")
            .font(.caption)
        }
      }
      .navigationTitle("Add Header")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save", action: onSave)
            .disabled(headerKey.isEmpty || headerValue.isEmpty)
        }
      }
    }
  }
}

extension CustomHeadersView {
  @Observable
  class Model: ObservableObject {
    struct Header: Identifiable {
      let id: String
      let key: String
      let value: String

      init(key: String, value: String) {
        self.id = key
        self.key = key
        self.value = value
      }
    }

    var headers: [Header]
    var showAddSheet: Bool
    var newHeaderKey: String
    var newHeaderValue: String

    func onAddHeaderTapped() {}
    func onSaveHeader() {}
    func onCancelAdd() {}
    func onDelete(at offsets: IndexSet) {}

    init(
      headers: [Header] = [],
      showAddSheet: Bool = false,
      newHeaderKey: String = "",
      newHeaderValue: String = ""
    ) {
      self.headers = headers
      self.showAddSheet = showAddSheet
      self.newHeaderKey = newHeaderKey
      self.newHeaderValue = newHeaderValue
    }
  }
}

extension CustomHeadersView.Model {
  static let mock = CustomHeadersView.Model()

  var headersCount: Int {
    headers.count
  }
}

#Preview {
  NavigationStack {
    CustomHeadersView(
      model: .init(
        headers: [
          .init(key: "X-API-Key", value: "abc123"),
          .init(key: "X-Custom-Header", value: "test-value"),
        ]
      )
    )
  }
}
