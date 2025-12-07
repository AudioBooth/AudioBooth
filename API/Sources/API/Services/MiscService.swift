import Foundation

public final class MiscService {
  private let audiobookshelf: Audiobookshelf

  enum Keys {
    static let ereaderDevices = "audiobookshelf_ereader_devices"
  }

  public var ereaderDevices: [EreaderDevice] {
    get {
      guard let data = UserDefaults.standard.data(forKey: Keys.ereaderDevices) else { return [] }
      let ereaderDevices = try? JSONDecoder().decode([EreaderDevice].self, from: data)
      return ereaderDevices ?? []
    }
    set {
      guard let data = try? JSONEncoder().encode(newValue) else { return }
      UserDefaults.standard.set(data, forKey: Keys.ereaderDevices)
    }
  }

  init(audiobookshelf: Audiobookshelf) {
    self.audiobookshelf = audiobookshelf
  }

  public func sendEbookToDevice(
    itemID: String,
    deviceName: String
  ) async throws {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first.")
    }

    struct EbookRequest: Codable {
      let libraryItemId: String
      let deviceName: String
    }

    let requestBody = EbookRequest(libraryItemId: itemID, deviceName: deviceName)

    let request = NetworkRequest<Data>(
      path: "/api/emails/send-ebook-to-device",
      method: .post,
      body: requestBody
    )

    _ = try await networkService.send(request)
  }
}
