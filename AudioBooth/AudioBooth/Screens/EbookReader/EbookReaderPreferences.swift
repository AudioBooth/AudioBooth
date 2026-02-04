import Combine
import Foundation
import ReadiumNavigator
import ReadiumShared
import SwiftUI

class EbookReaderPreferences: ObservableObject {
  @AppStorage("ebookReader.fontSize") var fontSize: Double = 1.0
  @AppStorage("ebookReader.fontWeight") var fontWeight: Double = 1.0
  @AppStorage("ebookReader.textNormalization") var textNormalization: Bool = false
  @AppStorage("ebookReader.fontFamily") var fontFamily: FontFamily = .system
  @AppStorage("ebookReader.theme") var theme: Theme = .light
  @AppStorage("ebookReader.pageMargins") var pageMargins: PageMargins = .medium
  @AppStorage("ebookReader.scroll") var verticalScrolling: Bool = false
  @AppStorage("ebookReader.tapToNavigate") var tapToNavigate: Bool = true

  @AppStorage("ebookReader.publisherStyles") var publisherStyles: Bool = true
  @AppStorage("ebookReader.lineHeight") var lineHeight: Double = 1.2
  @AppStorage("ebookReader.paragraphIndent") var paragraphIndent: Double = 0.0
  @AppStorage("ebookReader.paragraphSpacing") var paragraphSpacing: Double = 0.0
  @AppStorage("ebookReader.wordSpacing") var wordSpacing: Double = 0.0
  @AppStorage("ebookReader.letterSpacing") var letterSpacing: Double = 0.0

  enum FontFamily: String, CaseIterable, Identifiable {
    case system = "Original"
    case sansSerif = "Sans Serif"
    case iaWriterDuospace = "IA Writer Duospace"
    case accessibleDfA = "Accessible DfA"
    case openDyslexic = "OpenDyslexic"

    var id: String { rawValue }

    var readiumFontFamily: ReadiumNavigator.FontFamily? {
      switch self {
      case .system: return nil
      case .sansSerif: return .sansSerif
      case .iaWriterDuospace: return .iaWriterDuospace
      case .accessibleDfA: return .accessibleDfA
      case .openDyslexic: return .openDyslexic
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
}

extension EbookReaderPreferences {
  func toEPUBPreferences() -> EPUBPreferences {
    var prefs = EPUBPreferences()

    prefs.fontSize = max(0.1, fontSize)
    prefs.fontWeight = fontWeight
    prefs.textNormalization = textNormalization
    prefs.fontFamily = fontFamily.readiumFontFamily
    prefs.theme = theme.toReadiumTheme()
    prefs.pageMargins = pageMargins.value
    prefs.scroll = verticalScrolling

    prefs.publisherStyles = publisherStyles
    if !publisherStyles {
      prefs.lineHeight = lineHeight
      prefs.paragraphIndent = paragraphIndent
      prefs.paragraphSpacing = paragraphSpacing
      prefs.wordSpacing = wordSpacing
      prefs.letterSpacing = letterSpacing
    }

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
