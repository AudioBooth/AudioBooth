import Audiobookshelf
import SwiftData
import SwiftUI

struct SettingsView: View {
  @StateModel var model: Model

  init(model: Model? = nil) {
    if let model {
      self._model = StateModel(wrappedValue: model)
    } else {
      self._model = StateModel(mock: .mock, default: SettingsViewModel())
    }
  }

  var body: some View {
    NavigationStack(path: $model.navigationPath) {
      Form {
        Section("Server Configuration") {
          TextField("Server URL", text: $model.serverURL)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .disabled(model.isAuthenticated)

          if !model.isAuthenticated {
            HStack {
              TextField("Port", text: $model.discoveryPort)
                .keyboardType(.numberPad)
                .frame(maxWidth: 80)
                .disabled(model.isDiscovering)

              Button(action: model.onDiscoverServersTapped) {
                HStack {
                  if model.isDiscovering {
                    ProgressView()
                      .scaleEffect(0.8)
                  } else {
                    Image(systemName: "network")
                  }
                  Text(model.isDiscovering ? "Scanning network..." : "Discover Servers")
                }
              }
              .disabled(model.isDiscovering || model.discoveryPort.isEmpty)
            }
          }
        }

        if !model.discoveredServers.isEmpty && !model.isAuthenticated {
          Section("Discovered Servers") {
            ForEach(model.discoveredServers) { server in
              Button(action: { model.onServerSelected(server) }) {
                VStack(alignment: .leading, spacing: 4) {
                  HStack {
                    Text(server.serverURL.absoluteString)
                      .foregroundColor(.primary)
                    Spacer()
                    Text("\(Int(server.responseTime * 1000))ms")
                      .font(.caption)
                      .foregroundColor(.secondary)
                  }
                  if let info = server.serverInfo, let version = info.version {
                    Text("Version: \(version)")
                      .font(.caption)
                      .foregroundColor(.secondary)
                  }
                }
              }
            }
          }
        }

        if !model.isAuthenticated {
          authentication
        } else {
          account
        }

        #if DEBUG
          development
        #endif
      }
      .navigationTitle("Settings")
      .navigationDestination(for: String.self) { destination in
        switch destination {
        case "libraries":
          LibrariesView(model: model.library)
        default:
          EmptyView()
        }
      }
    }
  }

  @ViewBuilder
  var authentication: some View {
    Section("Authentication Method") {
      Picker("Method", selection: $model.authenticationMethod) {
        Text("Username & Password").tag(SettingsView.Model.AuthenticationMethod.usernamePassword)
        Text("OIDC (SSO)").tag(SettingsView.Model.AuthenticationMethod.oidc)
      }
      .pickerStyle(.segmented)
    }

    if model.authenticationMethod == .usernamePassword {
      Section("Credentials") {
        TextField("Username", text: $model.username)
          .autocorrectionDisabled()
          .textInputAutocapitalization(.never)

        SecureField("Password", text: $model.password)
      }

      Section {
        Button(action: model.onLoginTapped) {
          HStack {
            if model.isLoading {
              ProgressView()
                .scaleEffect(0.8)
            } else {
              Image(systemName: "person.badge.key")
            }
            Text(model.isLoading ? "Logging in..." : "Login")
          }
        }
        .disabled(
          model.username.isEmpty || model.password.isEmpty || model.serverURL.isEmpty
            || model.isLoading)
      }
    } else {
      Section {
        Button(action: model.onOIDCLoginTapped) {
          HStack {
            if model.isLoading {
              ProgressView()
                .scaleEffect(0.8)
            } else {
              Image(systemName: "globe")
            }
            Text(model.isLoading ? "Authenticating..." : "Login with SSO")
          }
        }
        .disabled(model.serverURL.isEmpty || model.isLoading)
      }
    }
  }

  @ViewBuilder
  var account: some View {
    Section("Library") {
      NavigationLink(value: "libraries") {
        HStack {
          Image(systemName: "books.vertical")
          Text("Library")
          Spacer()
          if let library = model.library.selected {
            Text(library.name)
              .foregroundColor(.secondary)
          } else {
            Text("None selected")
              .foregroundColor(.secondary)
          }
        }
      }
    }

    Section("Account") {
      HStack {
        Image(systemName: "checkmark.circle.fill")
          .foregroundColor(.green)
        Text("Authenticated")
        Spacer()
        Button("Logout", action: model.onLogoutTapped)
          .foregroundColor(.red)
      }
    }
  }

  @ViewBuilder
  var development: some View {
    Section("Development") {
      Button("Clear Persistent Storage", action: model.onClearStorageTapped)
        .foregroundColor(.red)

      Text(
        "Clears all cached data and files. Use this when schema changes cause app crashes. Requires app restart."
      )
      .font(.caption)
    }
  }
}

extension SettingsView {
  @Observable class Model {
    enum AuthenticationMethod: CaseIterable {
      case usernamePassword
      case oidc
    }

    var isLoading: Bool
    var isAuthenticated: Bool
    var isDiscovering: Bool
    var navigationPath = NavigationPath()

    var serverURL: String
    var username: String
    var password: String
    var discoveryPort: String
    var authenticationMethod: AuthenticationMethod
    var library: LibrariesView.Model
    var discoveredServers: [DiscoveredServer]

    @MainActor func onLoginTapped() {}
    @MainActor func onOIDCLoginTapped() {}
    @MainActor func onLogoutTapped() {}
    @MainActor func onClearStorageTapped() {}
    @MainActor func onDiscoverServersTapped() {}
    @MainActor func onServerSelected(_ server: DiscoveredServer) {}

    init(
      isAuthenticated: Bool = false,
      isLoading: Bool = false,
      isDiscovering: Bool = false,
      serverURL: String = "",
      username: String = "",
      password: String = "",
      discoveryPort: String = "13378",
      authenticationMethod: AuthenticationMethod = .usernamePassword,
      library: LibrariesView.Model,
      discoveredServers: [DiscoveredServer] = []
    ) {
      self.serverURL = serverURL
      self.username = username
      self.password = password
      self.discoveryPort = discoveryPort
      self.authenticationMethod = authenticationMethod
      self.isAuthenticated = isAuthenticated
      self.isLoading = isLoading
      self.isDiscovering = isDiscovering
      self.library = library
      self.discoveredServers = discoveredServers
    }
  }
}

extension SettingsView.Model {
  static var mock = SettingsView.Model(
    library: .mock
  )
}

#Preview("SettingsView - Authentication") {
  SettingsView(model: .mock)
}

#Preview("SettingsView - Authenticated with Library") {
  SettingsView(
    model: .init(
      isAuthenticated: true,
      serverURL: "https://192.168.0.1:13378",
      library: LibrariesView.Model(selected: .init(id: UUID().uuidString, name: "My Library"))
    )
  )
}

#Preview("SettingsView - Authenticated No Library") {
  SettingsView(
    model: .init(
      isAuthenticated: true,
      serverURL: "https://192.168.0.1:13378",
      library: LibrariesView.Model()
    )
  )
}
