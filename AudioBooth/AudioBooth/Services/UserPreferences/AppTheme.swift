import SwiftUI
import UIKit

enum AppTheme: String, CaseIterable {
  case sepia
  case system
  case pure

  var displayText: LocalizedStringResource {
    switch self {
    case .sepia: "Sepia"
    case .system: "System"
    case .pure: "Pure"
    }
  }

  var colors: Colors {
    switch self {
    case .sepia:
      Colors(
        background: Colors.Background(
          page: Color.Sepia.Background.page,
          card: Color.Sepia.Background.card
        )
      )
    case .system:
      Colors(
        background: Colors.Background(
          page: Color(.systemBackground),
          card: Color(.secondarySystemBackground)
        )
      )
    case .pure:
      Colors(
        background: Colors.Background(
          page: Color.Pure.Background.page,
          card: Color.Pure.Background.card
        )
      )
    }
  }
}

extension AppTheme {
  struct Colors {
    struct Background {
      var page: Color
      var card: Color
    }

    var background: Background
  }
}

extension EnvironmentValues {
  @Entry var appTheme: AppTheme = .sepia
}
