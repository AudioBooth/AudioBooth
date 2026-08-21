import Foundation
import Nuke

extension ImagePipeline {
  nonisolated static func audioBooth(customHeaders: [String: String]?) -> ImagePipeline {
    ImagePipeline {
      let configuration = DataLoader.defaultConfiguration
      configuration.urlCache = nil
      configuration.httpAdditionalHeaders = customHeaders
      $0.dataLoader = DataLoader(configuration: configuration)

      $0.dataCache = try? DataCache(name: "me.jgrenier.audioBS.images")
    }
  }
}
