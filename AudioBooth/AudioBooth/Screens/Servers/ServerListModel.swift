import API
import Foundation
import Logging
import Models
import SwiftUI

final class ServerListModel: ServerListPage.Model {
  private let audiobookshelf = Audiobookshelf.shared
  private var playerManager: PlayerManager { .shared }

  init(pendingExportConnection: DeepLinkManager.ExportConnection? = nil) {
    let allServers = audiobookshelf.authentication.servers.values
      .sorted { lhs, rhs in
        let lhsName = lhs.alias ?? (lhs.baseURL.host ?? "Unknown Server")
        let rhsName = rhs.alias ?? (rhs.baseURL.host ?? "Unknown Server")
        return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
      }

    let activeServerID = audiobookshelf.authentication.server?.id

    var selected: ServerView.Model?
    let serverModels = allServers.map { server in
      let viewModel = ServerViewModel(server: server)
      if server.id == activeServerID {
        selected = viewModel
      }
      return viewModel
    }

    if let exportConnection = pendingExportConnection {
      selected = ServerViewModel(exportConnection: exportConnection)
    }

    super.init(
      servers: serverModels,
      activeServerID: activeServerID,
      addServerModel: ServerViewModel(),
      selected: selected
    )
  }

  override func onAppear() {
    let allServers = audiobookshelf.authentication.servers.values
      .sorted { lhs, rhs in
        let lhsName = lhs.alias ?? (lhs.baseURL.host ?? "Unknown Server")
        let rhsName = rhs.alias ?? (rhs.baseURL.host ?? "Unknown Server")
        return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
      }
    servers = allServers.map { server in
      ServerViewModel(server: server)
    }
    activeServerID = audiobookshelf.authentication.server?.id
  }
}
