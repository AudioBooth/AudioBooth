import SwiftUI

struct AlphabetScrollBar: View {
  let availableSections: Set<String>
  let scrollProxy: ScrollViewProxy

  private let allLetters = [
    "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
    "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "#",
  ]

  @GestureState private var dragLocation: CGPoint = .zero
  @State private var lastScrolledLetter: String = ""

  private let haptics = UIImpactFeedbackGenerator(style: .light)

  var body: some View {
    VStack(spacing: 0) {
      ForEach(allLetters, id: \.self) { letter in
        Text(letter)
          .font(.caption2)
          .fontWeight(.semibold)
          .foregroundColor(.accentColor)
          .frame(minWidth: 30, alignment: .trailing)
          .padding(.trailing, 4)
          .contentShape(Rectangle())
          .background(dragObserver(for: letter))
      }
    }
    .background(Color.clear)
    .contentShape(Rectangle())
    .gesture(
      DragGesture(minimumDistance: 0, coordinateSpace: .global)
        .updating($dragLocation) { value, state, _ in
          state = value.location
        }
    )
  }

  private func dragObserver(for letter: String) -> some View {
    GeometryReader { geometry in
      Color.clear
        .onChange(of: dragLocation) { _, newLocation in
          if geometry.frame(in: .global).contains(newLocation) {
            scrollToLetter(letter)
          }
        }
    }
  }

  private func scrollToLetter(_ letter: String) {
    guard availableSections.contains(letter), letter != lastScrolledLetter else { return }

    lastScrolledLetter = letter
    haptics.impactOccurred()

    withAnimation(.easeOut(duration: 0.1)) {
      scrollProxy.scrollTo(letter, anchor: .top)
    }
  }
}
