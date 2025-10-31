import SwiftUI

final class CustomHeadersViewModel: CustomHeadersView.Model {
  var onHeadersChanged: (([String: String]) -> Void)?

  init(initialHeaders: [String: String] = [:]) {
    let headers = initialHeaders.map {
      CustomHeadersView.Model.Header(key: $0.key, value: $0.value)
    }
    .sorted { $0.key < $1.key }

    super.init(headers: headers)
  }

  override func onAddHeaderTapped() {
    newHeaderKey = ""
    newHeaderValue = ""
    showAddSheet = true
  }

  override func onSaveHeader() {
    let trimmedKey = newHeaderKey.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedValue = newHeaderValue.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmedKey.isEmpty, !trimmedValue.isEmpty else {
      showAddSheet = false
      return
    }

    if headers.contains(where: { $0.key == trimmedKey }) {
      headers.removeAll { $0.key == trimmedKey }
    }

    let newHeader = CustomHeadersView.Model.Header(key: trimmedKey, value: trimmedValue)
    headers.append(newHeader)
    headers.sort { $0.key < $1.key }

    showAddSheet = false
    notifyHeadersChanged()
  }

  override func onCancelAdd() {
    showAddSheet = false
    newHeaderKey = ""
    newHeaderValue = ""
  }

  override func onDelete(at offsets: IndexSet) {
    headers.remove(atOffsets: offsets)
    notifyHeadersChanged()
  }

  func getHeadersDictionary() -> [String: String] {
    Dictionary(uniqueKeysWithValues: headers.map { ($0.key, $0.value) })
  }

  private func notifyHeadersChanged() {
    onHeadersChanged?(getHeadersDictionary())
  }
}
