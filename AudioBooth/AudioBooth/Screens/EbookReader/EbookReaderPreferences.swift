import Combine
import Foundation
import ReadiumNavigator
import ReadiumShared
import SwiftUI

class EbookReaderPreferences: ObservableObject {
  @AppStorage("ebookReader.fontSize") var fontSize: FontSize = .medium
  @AppStorage("ebookReader.fontFamily") var fontFamily: FontFamily = .system
  @AppStorage("ebookReader.theme") var theme: Theme = .light
  @AppStorage("ebookReader.pageMargins") var pageMargins: PageMargins = .medium
  @AppStorage("ebookReader.lineSpacing") var lineSpacing: LineSpacing = .normal

  enum FontSize: String, CaseIterable, Identifiable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"
    case extraLarge = "Extra Large"

    var id: String { rawValue }

    var value: Double {
      switch self {
      case .small: return 0.8
      case .medium: return 1.0
      case .large: return 1.2
      case .extraLarge: return 1.5
      }
    }
  }

  enum FontFamily: String, CaseIterable, Identifiable {
    case system = "System"
    case serif = "Serif"
    case sansSerif = "Sans Serif"

    var id: String { rawValue }

    var fontName: String? {
      switch self {
      case .system: return nil
      case .serif: return "Georgia"
      case .sansSerif: return "Helvetica"
      }
    }
  }

  enum Theme: String, CaseIterable, Identifiable {
    case light = "Light"
    case dark = "Dark"
    case sepia = "Sepia"

    var id: String { rawValue }
  }

  enum PageMargins: String, CaseIterable, Identifiable {
    case narrow = "Narrow"
    case medium = "Medium"
    case wide = "Wide"

    var id: String { rawValue }

    var value: Double {
      switch self {
      case .narrow: return 0.5
      case .medium: return 1.0
      case .wide: return 1.5
      }
    }
  }

  enum LineSpacing: String, CaseIterable, Identifiable {
    case compact = "Compact"
    case normal = "Normal"
    case relaxed = "Relaxed"

    var id: String { rawValue }

    var value: Double {
      switch self {
      case .compact: return 1.2
      case .normal: return 1.5
      case .relaxed: return 1.8
      }
    }
  }
}

extension EbookReaderPreferences {
  func toEPUBPreferences() -> EPUBPreferences {
    var prefs = EPUBPreferences()

    prefs.fontSize = fontSize.value

    if let fontName = fontFamily.fontName {
      prefs.fontFamily = ReadiumNavigator.FontFamily(rawValue: fontName)
    }

    prefs.theme = theme.toReadiumTheme()

    prefs.pageMargins = pageMargins.value
    prefs.lineHeight = lineSpacing.value

    return prefs
  }
}

extension EbookReaderPreferences.Theme {
  func toReadiumTheme() -> ReadiumNavigator.Theme {
    switch self {
    case .light: return .light
    case .dark: return .dark
    case .sepia: return .sepia
    }
  }
}
