import Combine
import SwiftUI
import UIKit

struct EbookCoverView: View {
  @ObservedObject var model: Model

  @State private var showsControls = false

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    ZStack {
      if model.isVisible {
        cover
          .toolbar { toolbarContent }
          .onAppear(perform: revealControlsOnFirstAppear)
          .transition(.asymmetric(insertion: .identity, removal: .opacity))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .animation(.easeInOut(duration: 0.25), value: model.isVisible)
    .onHingeStateChange(model.onHingeChanged)
  }

  private func revealControlsOnFirstAppear() {
    guard model.revealsControlsOnAppear else { return }
    model.onAppear()
    withAnimation(.easeInOut(duration: 0.2)) { showsControls = true }
    Task {
      try? await Task.sleep(for: .seconds(2))
      withAnimation(.easeInOut(duration: 0.2)) { showsControls = false }
    }
  }

  @ToolbarContentBuilder
  private var toolbarContent: some ToolbarContent {
    ToolbarItem(placement: .topBarLeading) {
      if showsControls {
        Button(action: model.onReadTapped) {
          Label("Read", systemImage: "book.closed.fill")
        }
        .transition(.opacity)
        .tint(.primary)
      }
    }

    ToolbarItem(placement: .topBarTrailing) {
      if showsControls {
        Button {
          dismiss()
        } label: {
          Label("Close", systemImage: "xmark")
        }
        .transition(.opacity)
        .tint(.primary)
      }
    }
  }

  private var cover: some View {
    GeometryReader { proxy in
      let rotation = rotation
      let isSideways = abs(rotation.degrees) == 90

      ZStack {
        if let image = model.image {
          Color.clear
            .overlay {
              Image(uiImage: image)
                .resizable()
                .scaledToFill()
            }
            .clipped()
        } else if model.isLoaded {
          fallbackCover
        } else {
          Color.black
        }

        bookEffect
          .allowsHitTesting(false)
      }
      .frame(
        width: isSideways ? proxy.size.height : proxy.size.width,
        height: isSideways ? proxy.size.width : proxy.size.height
      )
      .rotationEffect(rotation)
      .frame(width: proxy.size.width, height: proxy.size.height)
      .transaction {
        $0.disablesAnimations = true
        $0.animation = nil
      }
    }
    .background(.black)
    .ignoresSafeArea()
    .contentShape(.rect)
    .onTapGesture {
      withAnimation(.easeInOut(duration: 0.2)) { showsControls.toggle() }
    }
  }

  private var rotation: Angle {
    let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
    switch windowScene?.effectiveGeometry.interfaceOrientation {
    case .landscapeLeft: return .degrees(90)
    case .landscapeRight: return .degrees(-90)
    case .portraitUpsideDown: return .degrees(180)
    default: return .zero
    }
  }

  private var fallbackCover: some View {
    VStack(spacing: 16) {
      Spacer()

      titles

      Spacer()
    }
    .padding(40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .overlay {
      Rectangle()
        .strokeBorder(.white.opacity(0.4), lineWidth: 1)
        .padding(20)
    }
    .background(fallbackColor)
  }

  private var titles: some View {
    VStack(spacing: 12) {
      if let title = model.title {
        Text(verbatim: title)
          .font(.system(.largeTitle, design: .serif, weight: .bold))
          .lineLimit(3)
          .minimumScaleFactor(0.6)
      }

      if let subtitle = model.subtitle {
        Text(verbatim: subtitle)
          .font(.system(.title3, design: .serif))
          .italic()
          .lineLimit(2)
          .opacity(0.8)
      }

      if let author = model.author {
        Text(verbatim: author)
          .font(.system(.headline, design: .serif, weight: .medium))
          .textCase(.uppercase)
          .lineLimit(2)
          .opacity(0.9)
          .padding(.top, 4)
      }
    }
    .multilineTextAlignment(.center)
    .foregroundStyle(.white)
  }

  private var fallbackColor: Color {
    let seed = (model.title ?? "").unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }
    let hue = Double(abs(seed % 360)) / 360
    return Color(hue: hue, saturation: 0.45, brightness: 0.4)
  }

  private var bookEffect: some View {
    ZStack {
      LinearGradient(
        stops: [
          .init(color: .black.opacity(0.35), location: 0),
          .init(color: .white.opacity(0.18), location: 0.015),
          .init(color: .black.opacity(0.25), location: 0.035),
          .init(color: .white.opacity(0.08), location: 0.06),
          .init(color: .clear, location: 0.12),
        ],
        startPoint: .leading,
        endPoint: .trailing
      )

      EllipticalGradient(
        colors: [.clear, .black.opacity(0.2)],
        center: .center,
        startRadiusFraction: 0.5,
        endRadiusFraction: 0.8
      )
    }
  }
}

extension EbookCoverView {
  @Observable
  class Model: ObservableObject {
    var image: UIImage?
    var title: String?
    var subtitle: String?
    var author: String?
    var hasHinge: Bool
    var isHingeClosed: Bool
    var isVisible: Bool
    var isLoaded: Bool
    var revealsControlsOnAppear: Bool

    func onAppear() {}
    func onHingeChanged(hasHinge: Bool, isClosed: Bool) {}
    func onReadTapped() {}

    init(
      image: UIImage? = nil,
      title: String? = nil,
      subtitle: String? = nil,
      author: String? = nil,
      hasHinge: Bool = false,
      isHingeClosed: Bool = false,
      isVisible: Bool = false,
      isLoaded: Bool = false,
      revealsControlsOnAppear: Bool = true
    ) {
      self.image = image
      self.title = title
      self.subtitle = subtitle
      self.author = author
      self.hasHinge = hasHinge
      self.isHingeClosed = isHingeClosed
      self.isVisible = isVisible
      self.isLoaded = isLoaded
      self.revealsControlsOnAppear = revealsControlsOnAppear
    }
  }
}
