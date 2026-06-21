import Combine
import SwiftUI

struct EbooksContent: View {
  @Environment(\.appTheme) var theme
  @ObservedObject var model: Model

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(model.ebooks, id: \.filename) { ebook in
        Button(action: { model.onEbookTapped(ebook) }) {
          HStack {
            Image(systemName: "book.closed.fill")
              .foregroundColor(Color.accentColor)

            VStack(alignment: .leading, spacing: 4) {
              Text(ebook.filename)
                .font(.subheadline)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)

              Text(
                ebook.size.formatted(
                  .byteCount(
                    style: .file,
                    allowedUnits: [.kb, .mb, .gb]
                  )
                )
              )
              .font(.caption)
              .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
              .font(.caption)
              .foregroundColor(.secondary)
          }
          .padding(.vertical, 8)
        }
        .contextMenu {
          if let shareItem = ebook.shareItem {
            ShareLink(item: shareItem, preview: SharePreview(ebook.filename)) {
              Label("Share", systemImage: "square.and.arrow.up")
            }
          }
        }
      }
    }
    .padding()
    .background(theme.colors.background.card)
    .cornerRadius(8)
    .fullScreenCover(item: $model.ebookReader) { readerModel in
      NavigationStack {
        EbookReaderView(model: readerModel)
      }
    }
  }
}

extension EbooksContent {
  @Observable
  class Model: ObservableObject {
    var ebooks: [SupplementaryEbook]
    var ebookReader: EbookReaderView.Model?

    func onEbookTapped(_ ebook: SupplementaryEbook) {}

    init(ebooks: [SupplementaryEbook]) {
      self.ebooks = ebooks
    }
  }

  struct SupplementaryEbook {
    let filename: String
    let size: Int64
    let ino: String
    var shareItem: BookShareItem? = nil
  }
}
