import Foundation

extension String {
  func cleaned() -> Self {
    return self.folding(options: .diacriticInsensitive, locale: .current)
  }
}

func sectionLetter(for name: String) -> String {
  let cleanedName = name.cleaned()
  guard let firstChar = cleanedName.uppercased().first else { return "#" }
  let validLetters: Set<Character> = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
  return validLetters.contains(firstChar) ? String(firstChar) : "#"
}
