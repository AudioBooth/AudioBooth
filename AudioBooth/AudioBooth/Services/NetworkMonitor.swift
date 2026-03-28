import API
import Foundation
import Network

final class NetworkMonitor {
  static let shared = NetworkMonitor()

  private let monitor = NWPathMonitor()
  private let queue = DispatchQueue(label: "me.jgrenier.AudioBS.NetworkMonitor")

  private(set) var isConnected = true
  private(set) var interfaceType: NWInterface.InterfaceType?

  private init() {
    monitor.pathUpdateHandler = { [weak self] path in
      self?.isConnected = path.status == .satisfied

      let previousInterfaceType = self?.interfaceType
      let newInterfaceType: NWInterface.InterfaceType?

      if path.usesInterfaceType(.wifi) {
        newInterfaceType = .wifi
      } else if path.usesInterfaceType(.cellular) {
        newInterfaceType = .cellular
      } else if path.usesInterfaceType(.wiredEthernet) {
        newInterfaceType = .wiredEthernet
      } else if path.usesInterfaceType(.loopback) {
        newInterfaceType = .loopback
      } else if path.usesInterfaceType(.other) {
        newInterfaceType = .other
      } else {
        newInterfaceType = nil
      }

      self?.interfaceType = newInterfaceType

      if previousInterfaceType != nil,
        newInterfaceType != nil,
        previousInterfaceType != newInterfaceType
      {
        self?.onNetworkInterfaceChanged()
      }
    }
    monitor.start(queue: queue)
  }

  private func onNetworkInterfaceChanged() {
    guard let server = Audiobookshelf.shared.authentication.server else { return }

    if server.urlMode == .fallback {
      server.urlMode = .primary
    }

    if server.status == .connectionError {
      Task {
        _ = try? await Audiobookshelf.shared.libraries.fetch(serverID: server.id)
      }
    }
  }
}
