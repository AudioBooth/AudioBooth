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

  var label: LocalizedStringResource {
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
  @AppStorage("ebookReader.customBackgroundColor") var customBackgroundColor: SwiftUI.Color = SwiftUI.Color(
    red: 0.23,
    green: 0.18,
    blue: 0.14
  )
  @AppStorage("ebookReader.customTextColor") var customTextColor: SwiftUI.Color = SwiftUI.Color(
    red: 0.94,
    green: 0.89,
    blue: 0.80
  )
  @AppStorage("ebookReader.pageMargins") var pageMargins: PageMargins = .medium
  @AppStorage("ebookReader.columnCount") var columnCount: ColumnCount = .auto
  @AppStorage("ebookReader.scroll") var scroll: Bool = false
  @AppStorage("ebookReader.tapToNavigate") var tapToNavigate: Bool = true
  @AppStorage("ebookReader.useVolumeButtonsForPageTurn") var useVolumeButtonsForPageTurn: Bool = false
  @AppStorage("ebookReader.autoScrollSpeed") var autoScrollSpeed: Double = 0.0
  @AppStorage("ebookReader.progressDisplay") var progressDisplay: EbookProgressDisplay = .percent
  @AppStorage("ebookReader.showProgressHeader") var showProgressHeader: Bool = true

  @AppStorage("ebookReader.readAlongFollows") var readAlongFollowsNarration: Bool = true
  @AppStorage("ebookReader.readAlongHighlightsWord") var readAlongHighlightsWord: Bool = true
  @AppStorage("ebookReader.readAlongHighlightsSentence") var readAlongHighlightsSentence: Bool = true

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
  @AppStorage("ebookReader.textAlign") var textAlign: TextAlign = .original

  enum FontFamily: String, CaseIterable, Identifiable {
    case system = "Original"
    case sansSerif = "Sans Serif"
    case iowanOldStyle = "Iowan Old Style"
    case palatino = "Palatino"
    case athelas = "Athelas"
    case georgia = "Georgia"
    case seravek = "Seravek"
    case helveticaNeue = "Helvetica Neue"
    case arial = "Arial"
    case iaWriterDuospace = "IA Writer Duospace"
    case accessibleDfA = "Accessible DfA"
    case openDyslexic = "OpenDyslexic"

    var id: String { rawValue }

    static let groups: [[FontFamily]] = [
      [.system, .sansSerif],
      [.iaWriterDuospace, .accessibleDfA, .openDyslexic],
      [.iowanOldStyle, .palatino, .athelas, .georgia, .seravek, .helveticaNeue, .arial],
    ]

    var readiumFontFamily: ReadiumNavigator.FontFamily? {
      switch self {
      case .system: return nil
      case .sansSerif: return .sansSerif
      case .iowanOldStyle: return .iowanOldStyle
      case .palatino: return .palatino
      case .athelas: return .athelas
      case .georgia: return .georgia
      case .seravek: return .seravek
      case .helveticaNeue: return .helveticaNeue
      case .arial: return .arial
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
    case gray = "Gray"
    case custom = "Custom"

    var id: String { rawValue }
  }

  enum ColumnCount: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case one = "1"
    case two = "2"

    var id: String { rawValue }

    var label: LocalizedStringResource {
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

  enum TextAlign: String, CaseIterable, Identifiable {
    case original = "Original"
    case left = "Left"
    case right = "Right"
    case justify = "Justify"

    var id: String { rawValue }

    var readiumTextAlign: ReadiumNavigator.TextAlignment? {
      switch self {
      case .original: nil
      case .left: .left
      case .right: .right
      case .justify: .justify
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
    prefs.theme = theme.toReadiumTheme(colorScheme: preferredColorScheme ?? colorScheme)
    switch theme {
    case .gray:
      prefs.backgroundColor = ReadiumNavigator.Color(rawValue: 0x323336)
      prefs.textColor = ReadiumNavigator.Color(rawValue: 0xD8D8D8)
    case .custom:
      prefs.backgroundColor = ReadiumNavigator.Color(uiColor: UIColor(customBackgroundColor))
      prefs.textColor = ReadiumNavigator.Color(uiColor: UIColor(customTextColor))
    default:
      break
    }
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

    if let readiumTextAlign = textAlign.readiumTextAlign {
      prefs.publisherStyles = false
      prefs.textAlign = readiumTextAlign
    }

    return prefs
  }

  var preferredColorScheme: ColorScheme? {
    guard theme == .custom else { return theme.colorScheme }

    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    UIColor(customBackgroundColor).getRed(&red, green: &green, blue: &blue, alpha: nil)
    let luminance = 0.299 * red + 0.587 * green + 0.114 * blue
    return luminance < 0.5 ? .dark : .light
  }
}

extension EbookReaderPreferences.Theme {
  var colorScheme: ColorScheme? {
    switch self {
    case .auto, .custom: return nil
    case .light, .sepia: return .light
    case .dark, .gray: return .dark
    }
  }

  func toReadiumTheme(colorScheme: ColorScheme) -> ReadiumNavigator.Theme {
    switch self {
    case .auto, .custom: return colorScheme == .dark ? .dark : .light
    case .light: return .light
    case .dark, .gray: return .dark
    case .sepia: return .sepia
    }
  }
}
