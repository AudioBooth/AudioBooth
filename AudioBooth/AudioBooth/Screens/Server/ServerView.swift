import API
import Combine
import SwiftUI

struct ServerView: View {
  enum FocusField: Hashable {
    case serverURL
    case username
    case password
  }

  @Environment(\.dismiss) var dismiss
  @FocusState private var focusedField: FocusField?

  @StateObject var model: Model

  var body: some View {
    NavigationStack(path: $model.navigationPath) {
      Form {
        if !model.isAuthenticated {
          discovery
        }

        Section("Server Configuration") {
          if !model.isTypingScheme {
            Picker("Protocol", selection: $model.serverScheme) {
              Text("https://").tag(ServerView.Model.ServerScheme.https)
              Text("http://").tag(ServerView.Model.ServerScheme.http)
            }
            .pickerStyle(.segmented)
            .disabled(model.isAuthenticated)
          }

          TextField("Server URL", text: $model.serverURL)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .disabled(model.isAuthenticated)
            .focused($focusedField, equals: .serverURL)
            .submitLabel(.next)
            .onSubmit {
              focusedField = .username
            }

          if !model.isAuthenticated {
            Toggle("Use Subdirectory", isOn: $model.useSubdirectory)

            if model.useSubdirectory {
              TextField("Subdirectory Path", text: $model.subdirectory)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            }
          }

          customHeadersSection
        }

        if !model.isAuthenticated {
          authentication
        } else {
          account
        }
      }
      .navigationTitle("Server")
      .navigationDestination(for: String.self) { destination in
        switch destination {
        case "customHeaders":
          CustomHeadersView(model: model.customHeaders)
        default:
          EmptyView()
        }
      }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(action: { dismiss() }) {
            Image(systemName: "xmark")
          }
        }
      }
      .alert("Scan Local Network", isPresented: $model.showDiscoveryPortAlert) {
        TextField("Discovery Port", text: $model.discoveryPort)
          .keyboardType(.numberPad)
        Button("Cancel", role: .cancel) {}
        Button("Scan") {
          if let viewModel = model as? ServerViewModel {
            viewModel.performDiscovery()
          }
        }
        .disabled(model.discoveryPort.isEmpty)
      } message: {
        Text("Enter the port number to scan for Audiobookshelf servers on your local network.")
      }
    }
  }

  @ViewBuilder
  var discovery: some View {
    Section("Network Discovery") {
      Button(action: model.onDiscoverServersTapped) {
        HStack {
          if model.isDiscovering {
            ProgressView()
              .scaleEffect(0.8)
          } else {
            Image(systemName: "network")
          }
          Text(model.isDiscovering ? "Scanning network..." : "Scan Local Network")
        }
      }
      .disabled(model.isDiscovering)

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

  @ViewBuilder
  var customHeadersSection: some View {
    if !model.isAuthenticated {
      NavigationLink(value: "customHeaders") {
        HStack {
          Image(systemName: "list.bullet.rectangle")
          Text("Custom Headers")
          Spacer()
          if model.customHeaders.headers.count > 0 {
            Text("\(model.customHeaders.headers.count)")
              .foregroundColor(.secondary)
          }
        }
      }
    }
  }

  @ViewBuilder
  var authentication: some View {
    Section("Authentication Method") {
      Picker("Method", selection: $model.authenticationMethod) {
        Text("Username & Password").tag(ServerView.Model.AuthenticationMethod.usernamePassword)
        Text("OIDC (SSO)").tag(ServerView.Model.AuthenticationMethod.oidc)
      }
      .pickerStyle(.segmented)
    }

    if model.authenticationMethod == .usernamePassword {
      Section("Credentials") {
        TextField("Username", text: $model.username)
          .autocorrectionDisabled()
          .textInputAutocapitalization(.never)
          .focused($focusedField, equals: .username)
          .submitLabel(.next)
          .onSubmit {
            focusedField = .password
          }

        SecureField("Password", text: $model.password)
          .focused($focusedField, equals: .password)
          .submitLabel(.send)
          .onSubmit {
            model.onLoginTapped()
          }
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
      if model.isLoadingLibraries {
        HStack {
          ProgressView()
            .scaleEffect(0.8)
          Text("Loading libraries...")
        }
      } else {
        ForEach(model.libraries) { library in
          Button(
            action: { model.onLibraryTapped(library) },
            label: {
              HStack {
                Text(library.name)
                  .font(.headline)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .foregroundStyle(Color.primary)

                if library.id == model.selectedLibrary?.id {
                  Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
                }
              }
            }
          )
          .padding(.vertical, 2)
        }
      }
    }

    Section("Account") {
      HStack {
        Image(systemName: "checkmark.circle.fill")
          .foregroundColor(.green)
        Text("Authenticated")
          .bold()
        Spacer()
        Button("Logout", action: model.onLogoutTapped)
          .foregroundColor(.red)
      }
    }
  }
}

extension ServerView {
  @Observable
  class Model: ObservableObject {
    enum AuthenticationMethod: CaseIterable {
      case usernamePassword
      case oidc
    }

    enum ServerScheme: String, CaseIterable {
      case https = "https://"
      case http = "http://"
    }

    struct Library: Identifiable {
      let id: String
      let name: String
    }

    var isLoading: Bool
    var isAuthenticated: Bool
    var isDiscovering: Bool
    var isLoadingLibraries: Bool
    var navigationPath = NavigationPath()
    var showDiscoveryPortAlert: Bool

    var serverURL: String
    var serverScheme: ServerScheme
    var useSubdirectory: Bool
    var subdirectory: String
    var username: String
    var password: String
    var customHeaders: CustomHeadersView.Model
    var discoveryPort: String
    var authenticationMethod: AuthenticationMethod
    var discoveredServers: [DiscoveredServer]
    var libraries: [Library]
    var selectedLibrary: Library?

    var isTypingScheme: Bool {
      let lowercased = serverURL.lowercased()
      return lowercased.hasPrefix("https://") || lowercased.hasPrefix("http://")
        || "https://".hasPrefix(lowercased) || "http://".hasPrefix(lowercased)
    }

    func onLoginTapped() {}
    func onOIDCLoginTapped() {}
    func onLogoutTapped() {}
    func onDiscoverServersTapped() {}
    func onServerSelected(_ server: DiscoveredServer) {}
    func onLibraryTapped(_ library: Library) {}

    init(
      isAuthenticated: Bool = false,
      isLoading: Bool = false,
      isDiscovering: Bool = false,
      isLoadingLibraries: Bool = false,
      showDiscoveryPortAlert: Bool = false,
      serverURL: String = "",
      serverScheme: ServerScheme = .https,
      useSubdirectory: Bool = false,
      subdirectory: String = "",
      username: String = "",
      password: String = "",
      customHeaders: CustomHeadersView.Model = .mock,
      discoveryPort: String = "13378",
      authenticationMethod: AuthenticationMethod = .usernamePassword,
      discoveredServers: [DiscoveredServer] = [],
      libraries: [Library] = [],
      selectedLibrary: Library? = nil
    ) {
      self.serverURL = serverURL
      self.serverScheme = serverScheme
      self.useSubdirectory = useSubdirectory
      self.subdirectory = subdirectory
      self.username = username
      self.password = password
      self.customHeaders = customHeaders
      self.discoveryPort = discoveryPort
      self.authenticationMethod = authenticationMethod
      self.isAuthenticated = isAuthenticated
      self.isLoading = isLoading
      self.isDiscovering = isDiscovering
      self.isLoadingLibraries = isLoadingLibraries
      self.showDiscoveryPortAlert = showDiscoveryPortAlert
      self.discoveredServers = discoveredServers
      self.libraries = libraries
      self.selectedLibrary = selectedLibrary
    }
  }
}

extension ServerView.Model {
  static var mock = ServerView.Model()
}

#Preview("ServerView - Authentication") {
  ServerView(model: .mock)
}

#Preview("ServerView - Authenticated with Library") {
  ServerView(
    model: .init(
      isAuthenticated: true,
      serverURL: "https://192.168.0.1:13378",
      libraries: [
        .init(id: UUID().uuidString, name: "My Library"),
        .init(id: UUID().uuidString, name: "Audiobooks"),
      ],
      selectedLibrary: .init(id: UUID().uuidString, name: "My Library")
    )
  )
}

#Preview("ServerView - Authenticated No Library") {
  ServerView(
    model: .init(
      isAuthenticated: true,
      serverURL: "https://192.168.0.1:13378"
    )
  )
}
