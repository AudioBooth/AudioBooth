import SwiftUI

private enum ResizeHandle: String, CaseIterable, Identifiable {
  case topLeft, topCenter, topRight
  case middleLeft, middleRight
  case bottomLeft, bottomCenter, bottomRight

  var id: String { rawValue }

  func position(in frame: CGRect) -> CGPoint {
    switch self {
    case .topLeft: CGPoint(x: frame.minX, y: frame.minY)
    case .topCenter: CGPoint(x: frame.midX, y: frame.minY)
    case .topRight: CGPoint(x: frame.maxX, y: frame.minY)
    case .middleLeft: CGPoint(x: frame.minX, y: frame.midY)
    case .middleRight: CGPoint(x: frame.maxX, y: frame.midY)
    case .bottomLeft: CGPoint(x: frame.minX, y: frame.maxY)
    case .bottomCenter: CGPoint(x: frame.midX, y: frame.maxY)
    case .bottomRight: CGPoint(x: frame.maxX, y: frame.maxY)
    }
  }

  var isCorner: Bool {
    switch self {
    case .topLeft, .topRight, .bottomLeft, .bottomRight: true
    default: false
    }
  }
}

struct EbookTapZonesEditorView: View {
  @ObservedObject var preferences: EbookReaderPreferences
  var onDone: () -> Void

  @State private var selectedAction: EbookTapAction = .nextPage
  @State private var dragStart: CGPoint?
  @State private var dragEnd: CGPoint?
  @State private var draggingZoneID: UUID?
  @State private var draggingTranslation: CGSize = .zero
  @State private var resizingZoneID: UUID?
  @State private var resizingHandle: ResizeHandle?
  @State private var resizingTranslation: CGSize = .zero

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .topLeading) {
        Color.black.opacity(0.6)
          .ignoresSafeArea()
          .overlay {
            Text("Taps outside zones show/hide controls")
              .font(.caption)
              .bold()
              .foregroundStyle(.white)
          }
          .gesture(drawGesture(in: geometry.size))

        ForEach(preferences.tapZones) { zone in
          zoneRect(zone: zone, in: geometry.size)
        }

        if let start = dragStart, let end = dragEnd {
          let rect = normalizedPreviewRect(from: start, to: end, in: geometry.size)
          let frame = denormalizedRect(rect, in: geometry.size)
          RoundedRectangle(cornerRadius: 8)
            .fill(selectedAction.color.opacity(0.3))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selectedAction.color, lineWidth: 2))
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
            .allowsHitTesting(false)
        }

        VStack {
          Spacer()
          bottomCard
        }
        .ignoresSafeArea(edges: .bottom)
      }
    }
    .ignoresSafeArea()
  }
}

extension EbookTapZonesEditorView {
  private func drawGesture(in size: CGSize) -> some Gesture {
    DragGesture(minimumDistance: 4, coordinateSpace: .local)
      .onChanged { value in
        if dragStart == nil { dragStart = value.startLocation }
        dragEnd = value.location
      }
      .onEnded { value in
        if let start = dragStart {
          let normalized = normalizedPreviewRect(from: start, to: value.location, in: size)
          if normalized.width * size.width >= 30, normalized.height * size.height >= 30 {
            preferences.tapZones.append(EbookTapZone(action: selectedAction, normalizedRect: normalized))
          }
        }
        dragStart = nil
        dragEnd = nil
      }
  }
}

extension EbookTapZonesEditorView {
  @ViewBuilder
  private func zoneRect(zone: EbookTapZone, in size: CGSize) -> some View {
    let frame = currentDisplayFrame(for: zone, in: size)

    RoundedRectangle(cornerRadius: 8)
      .fill(zone.action.color.opacity(0.25))
      .overlay(RoundedRectangle(cornerRadius: 8).stroke(zone.action.color, lineWidth: 2))
      .overlay(alignment: .bottomLeading) {
        Text(zone.action.label)
          .font(.caption2)
          .fontWeight(.medium)
          .foregroundStyle(.white)
          .padding(6)
      }
      .overlay(alignment: .topTrailing) {
        Button {
          preferences.tapZones.removeAll { $0.id == zone.id }
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.white, zone.action.color)
            .font(.system(size: 20))
        }
        .padding(4)
      }
      .frame(width: frame.width, height: frame.height)
      .offset(x: frame.minX, y: frame.minY)
      .simultaneousGesture(
        DragGesture(minimumDistance: 4)
          .onChanged { value in
            draggingZoneID = zone.id
            draggingTranslation = value.translation
          }
          .onEnded { value in
            if let index = preferences.tapZones.firstIndex(where: { $0.id == zone.id }) {
              preferences.tapZones[index].normalizedRect.origin.x += value.translation.width / size.width
              preferences.tapZones[index].normalizedRect.origin.y += value.translation.height / size.height
            }
            draggingZoneID = nil
            draggingTranslation = .zero
          }
      )

    ForEach(ResizeHandle.allCases) { handle in
      resizeHandleView(zone: zone, handle: handle, frame: frame, in: size)
    }
  }

  @ViewBuilder
  private func resizeHandleView(zone: EbookTapZone, handle: ResizeHandle, frame: CGRect, in size: CGSize) -> some View {
    let pos = handle.position(in: frame)
    let diameter: CGFloat = handle.isCorner ? 14 : 12

    Circle()
      .fill(.white)
      .frame(width: diameter, height: diameter)
      .overlay(Circle().stroke(zone.action.color, lineWidth: 2))
      .offset(x: pos.x - diameter / 2, y: pos.y - diameter / 2)
      .gesture(
        DragGesture(minimumDistance: 1)
          .onChanged { value in
            resizingZoneID = zone.id
            resizingHandle = handle
            resizingTranslation = value.translation
          }
          .onEnded { value in
            if let index = preferences.tapZones.firstIndex(where: { $0.id == zone.id }) {
              preferences.tapZones[index].normalizedRect = applyResize(
                to: preferences.tapZones[index].normalizedRect,
                handle: handle,
                translation: value.translation,
                in: size
              )
            }
            resizingZoneID = nil
            resizingHandle = nil
            resizingTranslation = .zero
          }
      )
  }
}

extension EbookTapZonesEditorView {
  private func currentDisplayFrame(for zone: EbookTapZone, in size: CGSize) -> CGRect {
    var normalized = zone.normalizedRect
    if draggingZoneID == zone.id {
      normalized.origin.x += draggingTranslation.width / size.width
      normalized.origin.y += draggingTranslation.height / size.height
    } else if resizingZoneID == zone.id, let handle = resizingHandle {
      normalized = applyResize(to: normalized, handle: handle, translation: resizingTranslation, in: size)
    }
    return denormalizedRect(normalized, in: size)
  }

  private func applyResize(to rect: CGRect, handle: ResizeHandle, translation t: CGSize, in size: CGSize) -> CGRect {
    let dx = t.width / size.width
    let dy = t.height / size.height
    var r = rect
    switch handle {
    case .topLeft:
      r.origin.x += dx; r.size.width -= dx
      r.origin.y += dy; r.size.height -= dy
    case .topCenter:
      r.origin.y += dy; r.size.height -= dy
    case .topRight:
      r.size.width += dx
      r.origin.y += dy; r.size.height -= dy
    case .middleLeft:
      r.origin.x += dx; r.size.width -= dx
    case .middleRight:
      r.size.width += dx
    case .bottomLeft:
      r.origin.x += dx; r.size.width -= dx
      r.size.height += dy
    case .bottomCenter:
      r.size.height += dy
    case .bottomRight:
      r.size.width += dx; r.size.height += dy
    }
    return r
  }
}

extension EbookTapZonesEditorView {
  private var bottomCard: some View {
    VStack(spacing: 12) {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(EbookTapAction.allCases) { action in
            Button {
              selectedAction = action
            } label: {
              Text(action.label)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(selectedAction == action ? action.color : Color.white.opacity(0.15))
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
          }
        }
        .padding(.horizontal)
      }

      HStack(spacing: 12) {
        Button("Reset") {
          preferences.resetTapZones()
        }
        .buttonStyle(.bordered)
        .tint(.white)

        Button("Done") {
          onDone()
        }
        .buttonStyle(.borderedProminent)
        .tint(.white)
        .foregroundStyle(.black)
      }
    }
    .padding(.vertical, 16)
    .frame(maxWidth: .infinity)
    .background(.ultraThinMaterial)
  }
}

extension EbookTapZonesEditorView {
  private func normalizedPreviewRect(from start: CGPoint, to end: CGPoint, in size: CGSize) -> CGRect {
    CGRect(
      x: min(start.x, end.x) / size.width,
      y: min(start.y, end.y) / size.height,
      width: abs(end.x - start.x) / size.width,
      height: abs(end.y - start.y) / size.height
    )
  }

  private func denormalizedRect(_ rect: CGRect, in size: CGSize) -> CGRect {
    CGRect(
      x: rect.minX * size.width,
      y: rect.minY * size.height,
      width: rect.width * size.width,
      height: rect.height * size.height
    )
  }
}
