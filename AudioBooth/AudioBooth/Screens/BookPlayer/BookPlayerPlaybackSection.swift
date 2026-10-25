import MediaPlayer
import SwiftUI

struct BookPlayerPlaybackSection: View {
  @ObservedObject var model: BookPlayer.Model
  @ObservedObject private var preferences = UserPreferences.shared

  var body: some View {
    VStack(spacing: 32) {
      PlaybackProgressView(model: $model.playbackProgress)
        .tint(progressTint)
      BookPlayerControls(model: model)
      if preferences.showSystemVolumeSlider {
        systemVolumeRow
      }
    }
  }

  private var systemVolumeRow: some View {
    HStack(spacing: 12) {
      Image(systemName: "speaker.fill")
        .accessibilityHidden(true)
      SystemVolumeSlider()
        .frame(height: 32)
      Image(systemName: "speaker.wave.3.fill")
        .accessibilityHidden(true)
    }
    .font(.footnote)
    .foregroundStyle(.secondary)
  }

  private var progressTint: Color? {
    guard preferences.coverColorProgressBar, let tint = model.progressTint else {
      return preferences.accentColor
    }
    return tint
  }
}

private struct SystemVolumeSlider: UIViewRepresentable {
  private static let thumb = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }
  private static let minimumTrack = trackImage(color: .secondaryLabel)
  private static let maximumTrack = trackImage(color: .systemFill)

  private static func trackImage(color: UIColor) -> UIImage {
    let size = CGSize(width: 7, height: 6)
    let image = UIGraphicsImageRenderer(size: size).image { _ in
      color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)).setFill()
      UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 3).fill()
    }
    return image.resizableImage(withCapInsets: UIEdgeInsets(top: 0, left: 3, bottom: 0, right: 3))
  }

  private final class CenteredVolumeView: MPVolumeView {
    override func volumeSliderRect(forBounds bounds: CGRect) -> CGRect {
      let rect = super.volumeSliderRect(forBounds: bounds)
      return CGRect(x: rect.minX, y: bounds.minY, width: rect.width, height: bounds.height)
    }
  }

  func makeUIView(context: Context) -> MPVolumeView {
    let volumeView = CenteredVolumeView()
    volumeView.setVolumeThumbImage(Self.thumb, for: .normal)
    volumeView.setMinimumVolumeSliderImage(Self.minimumTrack, for: .normal)
    volumeView.setMaximumVolumeSliderImage(Self.maximumTrack, for: .normal)
    return volumeView
  }

  func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
