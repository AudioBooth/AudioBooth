import API
import Combine
import SwiftUI

struct AuthenticationView: View {
  enum FocusField: Hashable {
    case username
    case password
  }

  @Environment(\.dismiss) var dismiss

  @FocusState private var focusedField: FocusField?

  @StateObject var model: Model

  var body: some View {
    if model.availableAuthMethods.count > 1 {
      Section("Authentication Method") {
        Picker("Method", selection: $model.authenticationMethod) {
          ForEach(model.availableAuthMethods, id: \.self) { method in
            switch method {
            case .usernamePassword:
              Text("Username & Password").tag(method)
            case .oidc:
              Text("OIDC (SSO)").tag(method)
            }
          }
        }
        .pickerStyle(.segmented)
      }
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
          model.username.isEmpty || model.password.isEmpty || model.isLoading
        )
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
        .disabled(model.isLoading)
      } footer: {
        Text("Add **audiobooth://oauth** to audiobookshelf server redirect URIs")
          .textSelection(.enabled)
          .font(.footnote)
      }
    }
  }
}

extension AuthenticationView {
  @Observable
  class Model: ObservableObject {
    enum AuthenticationMethod: CaseIterable, Hashable {
      case usernamePassword
      case oidc
    }

    var isLoading: Bool
    var username: String
    var password: String
    var authenticationMethod: AuthenticationMethod
    var availableAuthMethods: [AuthenticationMethod]
    var shouldAutoLaunchOIDC: Bool
    var onAuthenticationSuccess: () -> Void

    func onLoginTapped() {}
    func onOIDCLoginTapped() {}

    init(
      isLoading: Bool = false,
      username: String = "",
      password: String = "",
      authenticationMethod: AuthenticationMethod = .usernamePassword,
      availableAuthMethods: [AuthenticationMethod] = [.usernamePassword, .oidc],
      shouldAutoLaunchOIDC: Bool = false,
      onAuthenticationSuccess: @escaping () -> Void = {}
    ) {
      self.isLoading = isLoading
      self.username = username
      self.password = password
      self.authenticationMethod = authenticationMethod
      self.availableAuthMethods = availableAuthMethods
      self.shouldAutoLaunchOIDC = shouldAutoLaunchOIDC
      self.onAuthenticationSuccess = onAuthenticationSuccess
    }
  }
}

extension AuthenticationView.Model {
  static var mock = AuthenticationView.Model()
}

#Preview {
  NavigationStack {
    AuthenticationView(model: .mock)
  }
}
