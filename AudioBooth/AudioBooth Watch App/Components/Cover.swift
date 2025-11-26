import NukeUI
import SwiftUI

struct Cover: View {
  let url: URL?
  let state: DownloadManager.DownloadState

  var body: some View {
    LazyImage(url: url) { state in
      if let image = state.image {
        image
          .resizable()
          .aspectRatio(contentMode: .fit)
      } else {
        Color.gray
      }
    }
    .opacity(state == .downloaded ? 1.0 : 0.5)
    .overlay(alignment: .bottomTrailing) {
      download
    }
    .aspectRatio(1, contentMode: .fit)
    .clipShape(RoundedRectangle(cornerRadius: 6))
  }

  @ViewBuilder
  var download: some View {
    switch state {
    case .downloaded:
      EmptyView()
    case .downloading(let value):
      progress(value)
        //        .padding(2)
        .frame(width: 14, height: 14)
        .foregroundColor(.white)
        .padding(.trailing, 4)
        .padding(.bottom, 4)
        .background {
          DownloadBackground()
            .fill(.gray.opacity(0.8))
        }
    case .notDownloaded:
      Image(systemName: "arrow.down.to.line")
        .font(.system(size: 12, weight: .bold))
        .frame(width: 14, height: 14)
        .foregroundColor(.white)
        .padding(.trailing, 4)
        .padding(.bottom, 4)
        .background {
          DownloadBackground()
            .fill(.gray.opacity(0.8))
        }
    }
  }

  func progress(_ progress: Double) -> some View {
    ZStack {
      //      Circle()
      //        .stroke(Color.white.opacity(0.4), lineWidth: 2)
      //
      //      Circle()
      //        .trim(from: 0, to: progress)
      //        .stroke(
      //          Color.white,
      //          style: StrokeStyle(lineWidth: 2, lineCap: .round)
      //        )
      //        .rotationEffect(.degrees(-90))

      Text("\(Int(progress * 100))%")
        .font(.system(size: 8, weight: .bold))
        .monospacedDigit()
        .minimumScaleFactor(0.5)
        .foregroundColor(.white)
    }
  }
}

extension Cover {
  struct DownloadBackground: Shape {
    func path(in rect: CGRect) -> Path {
      var path = Path()

      path.move(to: CGPoint(x: rect.maxX, y: rect.minY - rect.maxY))
      path.addLine(to: CGPoint(x: rect.minX - rect.maxX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))

      return path
    }
  }
}

#Preview("Cover") {
  Cover(
    url: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"),
    state: .downloading(progress: 0.5)
  )
  .frame(width: 50, height: 50)

  Cover(
    url: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"),
    state: .notDownloaded
  )
  .frame(width: 50, height: 50)
}
