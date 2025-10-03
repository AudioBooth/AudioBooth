import AVFoundation
import Combine
import SwiftUI
import WatchKit

struct VolumeControl: WKInterfaceObjectRepresentable {
  let control: WKInterfaceVolumeControl = WKInterfaceVolumeControl(origin: .local)

  func makeWKInterfaceObject(context: Self.Context) -> WKInterfaceVolumeControl {
    control.focus()
    return control
  }

  func updateWKInterfaceObject(
    _ wkInterfaceObject: WKInterfaceVolumeControl,
    context: WKInterfaceObjectRepresentableContext<VolumeControl>
  ) {
    Task { @MainActor in
      wkInterfaceObject.focus()
    }
  }
}

struct VolumeView: View {
  @StateObject var model = Model()

  private let control = VolumeControl()

  var body: some View {
    ZStack {
      control
        .opacity(0.0)
        .focusable(true)

      GeometryReader { geometry in
        HStack(spacing: 2) {
          Spacer()
          ZStack(alignment: .leading) {
            Label("", systemImage: "speaker.wave.3.fill")
              .hidden()

            Label("", systemImage: volume)
          }
          .font(.system(size: 12))
          .labelStyle(.iconOnly)

          ZStack(alignment: .bottom) {
            Capsule()
              .foregroundStyle(.green.opacity(0.3))

            Capsule()
              .frame(height: min(max(40 * model.volume, 0), 40))
              .animation(.linear, value: model.volume)
          }
          .frame(width: 6, height: 40)
        }
        .foregroundStyle(.green)
        .padding(.top, 40)
      }
      .background(.ultraThinMaterial.opacity(0.8))
      .opacity(model.isHidden ? 0 : 1)
      .animation(.easeInOut, value: model.isHidden)
      .ignoresSafeArea(.all)
    }
  }

  var volume: String {
    if model.volume == 0 {
      return "speaker.slash.fill"
    } else if model.volume < 0.33 {
      return "speaker.wave.1.fill"
    } else if model.volume < 0.66 {
      return "speaker.wave.2.fill"
    } else {
      return "speaker.wave.3.fill"
    }
  }
}

extension VolumeView {
  @Observable
  class Model: ObservableObject {
    var volume: Double = 0.8
    var isHidden: Bool = true

    private var controlsTimer: Timer?
    private var observer: NSKeyValueObservation?

    init() {
      observer = AVAudioSession.sharedInstance().observe(\.outputVolume) { [weak self] session, _ in
        self?.volume = Double(session.outputVolume)
        self?.handleVolumeSliderAppearance()
      }
    }

    func handleVolumeSliderAppearance() {
      controlsTimer?.invalidate()

      isHidden = false
      controlsTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) {
        [weak self] timer in
        if self?.isHidden == false {
          self?.controlsTimer?.invalidate()
          self?.isHidden = true
        }
      }
    }
  }
}

#Preview {
  Cover(
    url: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"),
    state: .downloading
  )
  .frame(width: 100, height: 100)
  .frame(maxWidth: .infinity, maxHeight: .infinity)
  .overlay {
    VolumeView()
  }
}
