import Combine
import NukeUI
import SwiftUI

struct Cover: View {
  let model: Model
  let style: Style
  let size: Size

  init(model: Model, style: Style = .standard, size: Size = .medium) {
    self.model = model
    self.style = style
    self.size = size
  }

  init(url: URL?, style: Style = .standard, size: Size = .medium) {
    self.model = Model(url: url)
    self.style = style
    self.size = size
  }

  var body: some View {
    LazyImage(url: model.url) { state in
      if let image = state.image {
        image
          .resizable()
          .aspectRatio(contentMode: .fit)
      } else {
        placeholder
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .aspectRatio(style == .standard ? 1 : nil, contentMode: .fit)
    .background {
      if style == .standard {
        LazyImage(url: model.url) { state in
          state.image?
            .resizable()
            .aspectRatio(contentMode: .fill)
            .blur(radius: 5)
            .opacity(0.3)
        }
      }
    }
    .overlay { downloadOverlay }
    .overlay(alignment: .bottom) {
      ProgressOverlay(progress: model.progress)
        .padding(size.progressPadding)
    }
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(Color.gray.opacity(0.6), lineWidth: 1)
    }
    .id(model.url)
  }

  @ViewBuilder
  private var placeholder: some View {
    Color(.systemGray5)
      .overlay {
        RoundedRectangle(cornerRadius: 4)
          .stroke(Color.gray.opacity(0.4), lineWidth: 1)
          .padding(8)
      }
      .overlay {
        if let title = model.title, !title.isEmpty {
          VStack(spacing: 2) {
            Text(title)
              .font(.caption2)
              .fontWeight(.medium)
              .lineLimit(2)
            if let author = model.author, !author.isEmpty {
              Text(author)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
            }
          }
          .multilineTextAlignment(.center)
          .padding()
        } else {
          Image(systemName: "book.closed")
            .foregroundColor(.gray)
            .font(.title2)
        }
      }
  }

  @ViewBuilder
  private var downloadOverlay: some View {
    if let downloadProgress = model.downloadProgress {
      ZStack {
        Color.black.opacity(0.6)
        ProgressView(value: downloadProgress)
          .progressViewStyle(GaugeProgressViewStyle(tint: .white, lineWidth: 4))
          .frame(width: 20, height: 20)
      }
    }
  }
}

extension Cover {
  enum Style {
    case standard
    case plain
  }

  enum Size {
    case small
    case medium

    var progressPadding: CGFloat {
      switch self {
      case .small: 2
      case .medium: 4
      }
    }
  }

  @Observable
  class Model: ObservableObject {
    var url: URL?
    var title: String?
    var author: String?
    var progress: Double?
    var downloadProgress: Double?

    init(
      url: URL?,
      title: String? = nil,
      author: String? = nil,
      progress: Double? = nil,
      downloadProgress: Double? = nil
    ) {
      self.url = url
      self.title = title
      self.author = author
      self.progress = progress
      self.downloadProgress = downloadProgress
    }
  }
}

#Preview("Cover - Standard") {
  Cover(
    model: Cover.Model(
      url: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg")
    )
  )
  .frame(width: 120, height: 120)
  .shadow(radius: 2)
  .padding()
}

#Preview("Cover - Plain") {
  Cover(
    url: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"),
    style: .plain
  )
  .frame(width: 60, height: 60)
  .padding()
}

#Preview("Cover - Placeholder with Title") {
  Cover(
    model: Cover.Model(
      url: nil,
      title: "The Lord of the Rings",
      author: "J.R.R. Tolkien"
    )
  )
  .frame(width: 120, height: 120)
  .padding()
}

#Preview("Cover - Placeholder without Title") {
  Cover(url: nil)
    .frame(width: 120, height: 120)
    .padding()
}

#Preview("Cover - With Progress") {
  Cover(
    model: Cover.Model(
      url: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"),
      progress: 0.45
    )
  )
  .frame(width: 120, height: 120)
  .padding()
}

#Preview("Cover - Downloading") {
  Cover(
    model: Cover.Model(
      url: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"),
      downloadProgress: 0.65
    )
  )
  .frame(width: 120, height: 120)
  .padding()
}
