import API
import SwiftUI

final class LibrariesViewModel: LibrariesView.Model {
  private let audiobookshelf = Audiobookshelf.shared

  private var data: [Library] = []

  init() {
    let row: Row?
    if let current = audiobookshelf.libraries.current {
      row = Row(id: current.id, name: current.name)
    } else {
      row = nil
    }

    super.init(selected: row)
  }

  override func onAppear() {
    Task {
      await fetchLibraries()
    }
  }

  override func onRowTapped(_ row: Row) {
    guard
      row.id != selected?.id,
      let value = data.first(where: { $0.id == row.id })
    else { return }

    audiobookshelf.libraries.current = value

    selected = row
  }

  private func fetchLibraries() async {
    isLoading = true

    do {
      let libraries = try await audiobookshelf.libraries.fetch()

      data = libraries

      self.rows = data.map({ Row(id: $0.id, name: $0.name) })
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

      if rows.count == 1, let row = rows.first {
        onRowTapped(row)
      }
    } catch {
      Toast(error: "Failed to load libraries").show()
    }

    isLoading = false
  }
}
