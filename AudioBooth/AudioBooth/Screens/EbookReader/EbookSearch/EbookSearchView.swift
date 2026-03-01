import Combine
import ReadiumShared
import SwiftUI

struct EbookSearchView: View {
  @ObservedObject var model: Model
  @FocusState private var searchFieldFocused: Bool

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        SearchField(text: $model.query, isFocused: $searchFieldFocused)
          .padding()

        if model.isSearching {
          searchingView
        } else if model.results.isEmpty && !model.query.isEmpty {
          emptyResultsView
        } else if !model.results.isEmpty {
          resultsListView
        } else {
          emptyStateView
        }
      }
      .navigationTitle("Search")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Close", systemImage: "xmark") {
            model.onDismiss()
          }
          .tint(.primary)
        }
      }
      .onAppear {
        searchFieldFocused = true
      }
    }
  }

  private var searchingView: some View {
    VStack(spacing: 16) {
      ProgressView()
        .scaleEffect(1.2)
      Text("Searching...")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var emptyResultsView: some View {
    ContentUnavailableView {
      Label("No Results", systemImage: "magnifyingglass")
    } description: {
      Text("No matches found for '\(model.query)'")
    }
  }

  private var emptyStateView: some View {
    ContentUnavailableView {
      Label("Search Book", systemImage: "magnifyingglass")
    } description: {
      Text("Enter text to search within this book")
    }
  }

  private var resultsListView: some View {
    List {
      ForEach(Array(model.results.enumerated()), id: \.offset) { index, locator in
        resultRow(locator: locator, index: index)
          .onAppear {
            if index == model.results.count - 1 {
              model.onLoadNextPage()
            }
          }
      }

      if model.isLoadingMore {
        HStack {
          Spacer()
          ProgressView()
          Spacer()
        }
        .listRowSeparator(.hidden)
      }
    }
    .listStyle(.plain)
  }

  private func resultRow(locator: Locator, index: Int) -> some View {
    Button {
      model.onResultSelected(locator: locator, index: index)
    } label: {
      VStack(alignment: .leading, spacing: 8) {
        if let title = locator.title {
          Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        let text = locator.text.sanitized()
        (Text(text.before ?? "")
          + Text(text.highlight ?? "")
          .foregroundStyle(Color.accentColor)
          .fontWeight(.semibold)
          + Text(text.after ?? ""))
          .font(.body)
          .foregroundStyle(.primary)
          .multilineTextAlignment(.leading)
      }
      .padding(.vertical, 4)
    }
    .buttonStyle(.plain)
  }
}

private struct SearchField: View {
  @Binding var text: String
  var isFocused: FocusState<Bool>.Binding

  var body: some View {
    HStack {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)

      TextField("Search", text: $text)
        .focused(isFocused)
        .textFieldStyle(.plain)
        .autocorrectionDisabled()

      if !text.isEmpty {
        Button {
          text = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(8)
    .background(Color(.systemGray6))
    .cornerRadius(10)
  }
}

extension EbookSearchView {
  @Observable
  class Model: ObservableObject, Identifiable {
    let id = UUID()

    var query: String
    var results: [Locator]
    var isSearching: Bool
    var isLoadingMore: Bool

    func onResultSelected(locator: Locator, index: Int) {}
    func onLoadNextPage() {}
    func onDismiss() {}

    init(
      query: String = "",
      results: [Locator] = [],
      isSearching: Bool = false,
      isLoadingMore: Bool = false
    ) {
      self.query = query
      self.results = results
      self.isSearching = isSearching
      self.isLoadingMore = isLoadingMore
    }
  }
}
