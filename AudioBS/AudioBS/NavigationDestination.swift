import Foundation
import SwiftUI

enum NavigationDestination: Hashable {
  case book(id: String)
  case series(id: String, name: String)
  case author(id: String, name: String)
  case narrator(name: String)
  case genre(name: String)
  case tag(name: String)
  case offline
}
