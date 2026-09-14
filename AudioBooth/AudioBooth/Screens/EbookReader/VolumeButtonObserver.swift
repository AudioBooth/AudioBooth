import AVFoundation
import Combine
import MediaPlayer
import SwiftUI

struct VolumeButtonObserver: UIViewRepresentable {
  var onVolumeUp: () -> Void
  var onVolumeDown: () -> Void

  func makeUIView(context: Context) -> UIView {
    let view = UIView(frame: .zero)
    let volumeView = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
    volumeView.alpha = 0.0001
    volumeView.isUserInteractionEnabled = false
    view.addSubview(volumeView)
    context.coordinator.start(volumeView: volumeView)
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    context.coordinator.onVolumeUp = onVolumeUp
    context.coordinator.onVolumeDown = onVolumeDown
  }

  static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
    coordinator.stop()
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(onVolumeUp: onVolumeUp, onVolumeDown: onVolumeDown)
  }

  final class Coordinator: NSObject {
    var onVolumeUp: () -> Void
    var onVolumeDown: () -> Void
    private weak var volumeView: MPVolumeView?
    private var observer: NSKeyValueObservation?
    private var startTask: Task<Void, Never>?
    private var baseVolume: Float = 0.5

    private static let volumeStep: Float = 1.0 / 16.0

    init(onVolumeUp: @escaping () -> Void, onVolumeDown: @escaping () -> Void) {
      self.onVolumeUp = onVolumeUp
      self.onVolumeDown = onVolumeDown
    }

    func start(volumeView: MPVolumeView) {
      self.volumeView = volumeView

      startTask?.cancel()
      startTask = Task { [weak self] in
        await AudioSession.activate()
        guard let self, !Task.isCancelled else { return }

        let session = AVAudioSession.sharedInstance()
        baseVolume = clampedToStep(session.outputVolume)
        if baseVolume != session.outputVolume {
          setSystemVolume(baseVolume)
        }

        observer = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
          guard let self, let newVolume = change.newValue else { return }
          Task { @MainActor in
            self.handleVolumeChange(newVolume)
          }
        }
      }
    }

    func stop() {
      startTask?.cancel()
      startTask = nil
      observer?.invalidate()
      observer = nil
    }

    private func handleVolumeChange(_ newVolume: Float) {
      if newVolume > baseVolume {
        onVolumeUp()
      } else if newVolume < baseVolume {
        onVolumeDown()
      } else {
        return
      }
      setSystemVolume(baseVolume)
    }

    private func setSystemVolume(_ value: Float) {
      guard let slider = volumeView?.subviews.first(where: { $0 is UISlider }) as? UISlider else { return }
      slider.setValue(value, animated: false)
    }

    private func clampedToStep(_ value: Float) -> Float {
      let step = Self.volumeStep
      let minStep = step * 2
      let maxStep = 1 - step * 2
      let clamped = min(max(value, minStep), maxStep)
      return (clamped / step).rounded() * step
    }
  }
}
