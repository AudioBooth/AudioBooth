import AppIntents
import Models
import PlayerIntents
import SwiftUI
import WidgetKit

struct LargeWidgetView: View {
  let entry: AudioBoothWidgetEntry
  let books: [BookListEntry]

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Listen now")
        .font(.title3)
        .fontWeight(.bold)
        .foregroundStyle(.white)

      VStack(spacing: 10) {
        ForEach(Array(books.enumerated()), id: \.element.bookID) { index, book in
          Link(destination: URL(string: "audiobooth://open/\(book.bookID)")!) {
            BookRow(entry: entry, book: book)
          }
          .buttonStyle(.plain)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

struct BookRow: View {
  let entry: AudioBoothWidgetEntry
  let book: BookListEntry

  var body: some View {
    HStack(spacing: 12) {
      if let coverImage = entry.recentBookImages[book.bookID] {
        Image(uiImage: coverImage)
          .resizable()
          .aspectRatio(contentMode: .fill)
          .frame(width: 50, height: 50)
          .clipShape(RoundedRectangle(cornerRadius: 8))
      } else {
        RoundedRectangle(cornerRadius: 8)
          .fill(Color.gray.opacity(0.3))
          .frame(width: 50, height: 50)
          .overlay(
            Image(systemName: "book.fill")
              .font(.system(size: 20))
              .foregroundStyle(.white.opacity(0.5))
          )
      }

      VStack(alignment: .leading, spacing: 4) {
        Text(book.title)
          .font(.caption2)
          .fontWeight(.semibold)
          .foregroundStyle(.white)
          .lineLimit(1)

        Text(book.author)
          .font(.caption)
          .foregroundStyle(.white.opacity(0.8))
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Group {
        if let playbackState = entry.playbackState,
          playbackState.bookID == book.bookID,
          playbackState.isPlaying
        {
          Button(intent: PausePlaybackIntent()) {
            Image(systemName: "pause.circle.fill")
              .font(.system(size: 32))
              .foregroundStyle(.white)
          }
          .buttonStyle(.plain)
        } else {
          Button(intent: PlayBookIntent(bookID: book.bookID)) {
            Image(systemName: "play.circle.fill")
              .font(.system(size: 32))
              .foregroundStyle(.white)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }
}
