import API
import Combine
import SwiftUI

struct ServerListPage: View {
  @Environment(\.dismiss) var dismiss
  @StateObject var model: Model

  func statusColor(for status: Server.Status?) -> Color {
    switch status {
    case .connected:
      return .green
    case .connectionError:
      return .orange
    case .authenticationError:
      return .red
    case .none:
      return .gray
    }
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          if model.servers.isEmpty {
            Text("No servers connected")
              .foregroundColor(.secondary)
          } else {
            ForEach(model.servers, id: \.id) { server in
              Button {
                model.selected = server
              } label: {
                HStack {
                  Text("●")
                    .foregroundStyle(statusColor(for: server.status))

                  VStack(alignment: .leading, spacing: 4) {
                    if !server.alias.isEmpty {
                      Text(server.alias)
                        .font(.headline)
                        .foregroundColor(.primary)
                    } else {
                      Text(server.serverURL)
                        .font(.headline)
                        .foregroundColor(.primary)
                    }
                    Text(server.serverURL)
                      .font(.caption)
                      .foregroundColor(.secondary)
                  }

                  Spacer()

                  if server.selectedLibrary != nil {
                    Image(systemName: "checkmark.circle.fill")
                      .foregroundColor(Color.accentColor)
                  }
                }
              }
            }
          }

          Button {
            model.selected = model.addServerModel
          } label: {
            Label("Add Server", systemImage: "plus.circle.fill")
          }
        }
      }
      .navigationTitle("Servers")
      .navigationDestination(item: $model.selected) { model in
        ServerView(model: model)
      }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(action: { dismiss() }) {
            Label("Close", systemImage: "xmark")
          }
          .tint(.primary)
        }
      }
      .onAppear(perform: model.onAppear)
    }
  }
}

extension ServerListPage {
  @Observable
  class Model: ObservableObject {
    var servers: [ServerView.Model]
    var activeServerID: String?
    var addServerModel: ServerView.Model

    var selected: ServerView.Model?

    func onAppear() {}

    init(
      servers: [ServerView.Model] = [],
      activeServerID: String? = nil,
      addServerModel: ServerView.Model = .mock,
      selected: ServerView.Model? = nil
    ) {
      self.servers = servers
      self.activeServerID = activeServerID
      self.addServerModel = addServerModel
      self.selected = selected
    }
  }
}

extension ServerListPage.Model {
  static var mock = ServerListPage.Model()
}
