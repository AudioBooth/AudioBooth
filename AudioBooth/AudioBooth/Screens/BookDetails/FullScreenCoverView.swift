import Nuke
import SwiftUI
import UIKit

struct FullScreenCoverView: View {
  let coverURL: URL

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ZoomableImageView(coverURL: coverURL)
        .background(Color.black)
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button {
              dismiss()
            } label: {
              Label("Close", systemImage: "xmark")
            }
          }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
    }
  }
}

private struct ZoomableImageView: UIViewRepresentable {
  let coverURL: URL

  func makeUIView(context: Context) -> UIScrollView {
    let scrollView = UIScrollView()
    scrollView.delegate = context.coordinator
    scrollView.minimumZoomScale = 1.0
    scrollView.maximumZoomScale = 4.0
    scrollView.showsVerticalScrollIndicator = false
    scrollView.showsHorizontalScrollIndicator = false
    scrollView.backgroundColor = .black

    let imageView = UIImageView()
    imageView.contentMode = .scaleAspectFit
    imageView.isUserInteractionEnabled = true

    scrollView.addSubview(imageView)
    context.coordinator.imageView = imageView

    let doubleTap = UITapGestureRecognizer(
      target: context.coordinator,
      action: #selector(Coordinator.handleDoubleTap(_:))
    )
    doubleTap.numberOfTapsRequired = 2
    scrollView.addGestureRecognizer(doubleTap)

    let request = ImageRequest(url: coverURL)
    Task {
      if let image = try? await ImagePipeline.shared.image(for: request) {
        await MainActor.run {
          imageView.image = image
          context.coordinator.updateImageViewFrame(in: scrollView)
        }
      }
    }

    return scrollView
  }

  func updateUIView(_ scrollView: UIScrollView, context: Context) {
    context.coordinator.updateImageViewFrame(in: scrollView)
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  class Coordinator: NSObject, UIScrollViewDelegate {
    weak var imageView: UIImageView?

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func updateImageViewFrame(in scrollView: UIScrollView) {
      guard let imageView = imageView, imageView.image != nil else { return }

      let size = scrollView.bounds.size
      imageView.frame = CGRect(origin: .zero, size: size)
      scrollView.contentSize = size
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
      guard let imageView = imageView else { return }

      let offsetX = max((scrollView.bounds.width - scrollView.contentSize.width) * 0.5, 0)
      let offsetY = max((scrollView.bounds.height - scrollView.contentSize.height) * 0.5, 0)
      imageView.center = CGPoint(
        x: scrollView.contentSize.width * 0.5 + offsetX,
        y: scrollView.contentSize.height * 0.5 + offsetY
      )
    }

    @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
      guard let scrollView = gesture.view as? UIScrollView else { return }

      if scrollView.zoomScale > 1.0 {
        scrollView.setZoomScale(1.0, animated: true)
      } else {
        let location = gesture.location(in: scrollView)
        let zoomRect = CGRect(
          x: location.x - 50,
          y: location.y - 50,
          width: 100,
          height: 100
        )
        scrollView.zoom(to: zoomRect, animated: true)
      }
    }
  }
}
