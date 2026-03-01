import Foundation
import SwiftUI

enum NavigationDestination: Hashable {
  case book(id: String)
  case podcast(id: String, episodeID: String? = nil)
  case series(id: String, name: String, libraryID: String? = nil)
  case author(id: String, name: String, libraryID: String? = nil)
  case authorLibrary(id: String, name: String, libraryID: String? = nil)
  case narrator(name: String, libraryID: String? = nil)
  case genre(name: String, libraryID: String? = nil)
  case tag(name: String, libraryID: String? = nil)
  case playlist(id: String)
  case collection(id: String)
  case offline
  case stats
}
