import API
import Combine
import SwiftData
import SwiftUI
import UIKit

struct SettingsView: View {
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
              Text("https://").tag(SettingsView.Model.ServerScheme.https)
              Text("http://").tag(SettingsView.Model.ServerScheme.http)
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

          customHeadersSection
        }

        if !model.isAuthenticated {
          authentication
        } else {
          account
        }

        #if DEBUG
          development
        #endif

        Section {
          Text(model.appVersion)
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
        }
      }
      .navigationTitle("Settings")
      .navigationDestination(for: String.self) { destination in
        switch destination {
        case "libraries":
          LibrariesView(model: model.library)
        case "mediaProgress":
          if let model = model.mediaProgressList {
            MediaProgressListView(model: model)
          }
        case "customHeaders":
          CustomHeadersView(model: model.customHeaders)
        default:
          EmptyView()
        }
      }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Close") {
            dismiss()
          }
        }
      }
      .onChange(of: model.library.selected?.id) { oldValue, newValue in
        if oldValue == nil, newValue != nil {
          dismiss()
        }
      }
      .alert("Scan Local Network", isPresented: $model.showDiscoveryPortAlert) {
        TextField("Discovery Port", text: $model.discoveryPort)
          .keyboardType(.numberPad)
        Button("Cancel", role: .cancel) {}
        Button("Scan") {
          if let viewModel = model as? SettingsViewModel {
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
          if model.customHeaders.headersCount > 0 {
            Text("\(model.customHeaders.headersCount)")
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

    Section("Preferences") {
      Toggle("Show Listening Stats", isOn: $model.showListeningStats)
    }

    TipJarView(model: model.tipJar)

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
      NavigationLink(value: "mediaProgress") {
        HStack {
          Image(systemName: "chart.line.uptrend.xyaxis")
          Text("Media Progress")
        }
      }

      Button(action: model.onExportLogsTapped) {
        HStack {
          if model.isExportingLogs {
            ProgressView()
              .scaleEffect(0.8)
          } else {
            Image(systemName: "square.and.arrow.up")
          }
          Text(model.isExportingLogs ? "Exporting..." : "Export Logs")
        }
      }
      .disabled(model.isExportingLogs)

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
  @Observable class Model: ObservableObject {
    enum AuthenticationMethod: CaseIterable {
      case usernamePassword
      case oidc
    }

    enum ServerScheme: String, CaseIterable {
      case https = "https://"
      case http = "http://"
    }

    var isLoading: Bool
    var isAuthenticated: Bool
    var isDiscovering: Bool
    var navigationPath = NavigationPath()
    var showDiscoveryPortAlert: Bool

    var serverURL: String
    var serverScheme: ServerScheme
    var username: String
    var password: String
    var customHeaders: CustomHeadersView.Model
    var discoveryPort: String
    var authenticationMethod: AuthenticationMethod
    var library: LibrariesView.Model
    var tipJar: TipJarView.Model
    var discoveredServers: [DiscoveredServer]
    var mediaProgressList: MediaProgressListView.Model?
    var isExportingLogs: Bool

    @ObservationIgnored
    @AppStorage("showListeningStats") var showListeningStats: Bool = false

    var isTypingScheme: Bool {
      let lowercased = serverURL.lowercased()
      return lowercased.hasPrefix("https://") || lowercased.hasPrefix("http://")
        || "https://".hasPrefix(lowercased) || "http://".hasPrefix(lowercased)
    }

    var appVersion: String {
      let version =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
      let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
      return "Version \(version) (\(build))"
    }

    func onLoginTapped() {}
    func onOIDCLoginTapped() {}
    func onLogoutTapped() {}
    func onClearStorageTapped() {}
    func onDiscoverServersTapped() {}
    func onServerSelected(_ server: DiscoveredServer) {}
    func onExportLogsTapped() {}

    init(
      isAuthenticated: Bool = false,
      isLoading: Bool = false,
      isDiscovering: Bool = false,
      showDiscoveryPortAlert: Bool = false,
      serverURL: String = "",
      serverScheme: ServerScheme = .https,
      username: String = "",
      password: String = "",
      customHeaders: CustomHeadersView.Model = .mock,
      discoveryPort: String = "13378",
      authenticationMethod: AuthenticationMethod = .usernamePassword,
      library: LibrariesView.Model,
      tipJar: TipJarView.Model = .mock,
      discoveredServers: [DiscoveredServer] = [],
      mediaProgressList: MediaProgressListView.Model? = nil,
      isExportingLogs: Bool = false
    ) {
      self.serverURL = serverURL
      self.serverScheme = serverScheme
      self.username = username
      self.password = password
      self.customHeaders = customHeaders
      self.discoveryPort = discoveryPort
      self.authenticationMethod = authenticationMethod
      self.isAuthenticated = isAuthenticated
      self.isLoading = isLoading
      self.isDiscovering = isDiscovering
      self.showDiscoveryPortAlert = showDiscoveryPortAlert
      self.library = library
      self.tipJar = tipJar
      self.discoveredServers = discoveredServers
      self.mediaProgressList = mediaProgressList
      self.isExportingLogs = isExportingLogs
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
