import Foundation

nonisolated enum BookLanguage {
  static func locale(for raw: String?) -> Locale? {
    guard let code = code(for: raw) else { return nil }
    return Locale(identifier: code)
  }

  static func code(for raw: String?) -> String? {
    guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
      return nil
    }

    if raw.contains("-") || raw.contains("_") {
      return raw.replacingOccurrences(of: "_", with: "-")
    }

    if raw.count <= 3 {
      return Locale.LanguageCode(raw.lowercased()).identifier(.alpha2) ?? raw.lowercased()
    }

    let english = Locale(identifier: "en")
    return Locale.LanguageCode.isoLanguageCodes.first { code in
      let identifier = code.identifier
      let englishName = english.localizedString(forLanguageCode: identifier)
      let nativeName = Locale(identifier: identifier).localizedString(forLanguageCode: identifier)
      return englishName?.caseInsensitiveCompare(raw) == .orderedSame
        || nativeName?.caseInsensitiveCompare(raw) == .orderedSame
    }?.identifier
  }
}
