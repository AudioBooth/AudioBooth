import Combine
import Foundation
import ReadiumNavigator
import ReadiumShared
import SwiftUI

enum EbookTapAction: String, CaseIterable, Identifiable, Codable {
  case previousPage
  case nextPage
  case playPause
  case jumpForward
  case jumpBackward
  case autoScrollPlayPause

  var id: String { rawValue }

  var label: String {
    switch self {
    case .previousPage: "Previous Page"
    case .nextPage: "Next Page"
    case .playPause: "Play / Pause"
    case .jumpForward: "Jump Forward"
    case .jumpBackward: "Jump Backward"
    case .autoScrollPlayPause: "Auto Scroll Play / Pause"
    }
  }

  var color: SwiftUI.Color {
    switch self {
    case .previousPage: .blue
    case .nextPage: .green
    case .playPause: .purple
    case .jumpForward: .orange
    case .jumpBackward: .orange
    case .autoScrollPlayPause: .teal
    }
  }
}

struct EbookTapZone: Identifiable, Codable {
  var id: UUID
  var action: EbookTapAction
  var normalizedRect: CGRect

  init(id: UUID = UUID(), action: EbookTapAction, normalizedRect: CGRect) {
    self.id = id
    self.action = action
    self.normalizedRect = normalizedRect
  }
}

enum EbookProgressDisplay: String, CaseIterable {
  case percent
  case page
}

private let defaultTapZones: [EbookTapZone] = [
  EbookTapZone(action: .previousPage, normalizedRect: CGRect(x: 0, y: 0, width: 0.25, height: 1)),
  EbookTapZone(action: .nextPage, normalizedRect: CGRect(x: 0.75, y: 0, width: 0.25, height: 1)),
]

class EbookReaderPreferences: ObservableObject {
  @AppStorage("ebookReader.fontSize") var fontSize: Double = 1.0
  @AppStorage("ebookReader.fontWeight") var fontWeight: Double = 1.0
  @AppStorage("ebookReader.textNormalization") var textNormalization: Bool = false
  @AppStorage("ebookReader.fontFamily") var fontFamily: FontFamily = .system
  @AppStorage("ebookReader.theme") var theme: Theme = .auto
  @AppStorage("ebookReader.pageMargins") var pageMargins: PageMargins = .medium
  @AppStorage("ebookReader.columnCount") var columnCount: ColumnCount = .auto
  @AppStorage("ebookReader.scroll") var scroll: Bool = false
  @AppStorage("ebookReader.tapToNavigate") var tapToNavigate: Bool = true
  @AppStorage("ebookReader.autoScrollSpeed") var autoScrollSpeed: Double = 0.0
  @AppStorage("ebookReader.progressDisplay") var progressDisplay: EbookProgressDisplay = .percent

  @AppStorage("ebookReader.tapZonesData") private var tapZonesData: Data = Data()

  var tapZones: [EbookTapZone] {
    get {
      guard !tapZonesData.isEmpty,
        let zones = try? JSONDecoder().decode([EbookTapZone].self, from: tapZonesData)
      else { return defaultTapZones }
      return zones
    }
    set {
      tapZonesData = (try? JSONEncoder().encode(newValue)) ?? Data()
    }
  }

  func resetTapZones() {
    tapZonesData = Data()
  }

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
    case auto = "Auto"
    case light = "Light"
    case dark = "Dark"
    case sepia = "Sepia"

    var id: String { rawValue }
  }

  enum ColumnCount: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case one = "1"
    case two = "2"

    var id: String { rawValue }

    var label: String {
      switch self {
      case .auto: "Auto"
      case .one: "1 Column"
      case .two: "2 Columns"
      }
    }

    var readiumColumnCount: ReadiumNavigator.ColumnCount {
      switch self {
      case .auto: .auto
      case .one: .one
      case .two: .two
      }
    }
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
  func toEPUBPreferences(colorScheme: ColorScheme) -> EPUBPreferences {
    var prefs = EPUBPreferences()

    prefs.fontSize = max(0.1, fontSize)
    prefs.fontWeight = fontWeight
    prefs.textNormalization = textNormalization
    prefs.fontFamily = fontFamily.readiumFontFamily
    prefs.theme = theme.toReadiumTheme(colorScheme: colorScheme)
    prefs.pageMargins = pageMargins.value
    prefs.scroll = scroll
    prefs.columnCount = columnCount.readiumColumnCount

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
  var colorScheme: ColorScheme? {
    switch self {
    case .auto: return nil
    case .light, .sepia: return .light
    case .dark: return .dark
    }
  }

  func toReadiumTheme(colorScheme: ColorScheme) -> ReadiumNavigator.Theme {
    switch self {
    case .auto: return colorScheme == .dark ? .dark : .light
    case .light: return .light
    case .dark: return .dark
    case .sepia: return .sepia
    }
  }
}
