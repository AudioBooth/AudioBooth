import SwiftUI

struct MetadataSection: View {
  let model: Model

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Metadata")
        .font(.headline)

      VStack(alignment: .leading, spacing: 8) {
        if let publisher = model.publisher {
          HStack {
            Image(systemName: "building.2")
              .accessibilityHidden(true)
            Text("**Publisher:** \(publisher)")
          }
          .font(.subheadline)
        }

        if let publishedYear = model.publishedYear {
          HStack {
            Image(systemName: "calendar")
              .accessibilityHidden(true)
            Text("**Published:** \(publishedYear)")
          }
          .font(.subheadline)
        }

        if let language = model.language {
          HStack {
            Image(systemName: "globe")
              .accessibilityHidden(true)
            Text("**Language:** \(language)")
          }
          .font(.subheadline)
        }

        if let duration = model.durationText {
          HStack {
            Image(systemName: "clock")
              .accessibilityHidden(true)
            Text("**Duration:** \(duration)")
          }
          .font(.subheadline)
        }

        if let size = model.size {
          HStack {
            Image(systemName: "internaldrive")
              .accessibilityHidden(true)
            Text("**Size:** \(size)")
          }
          .font(.subheadline)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

extension MetadataSection {
  struct Model {
    var publisher: String?
    var publishedYear: String?
    var language: String?
    var durationText: String?
    var size: String?
    var hasAudio: Bool
    var isEbook: Bool

    init(
      publisher: String? = nil,
      publishedYear: String? = nil,
      language: String? = nil,
      durationText: String? = nil,
      size: String? = nil,
      hasAudio: Bool = false,
      isEbook: Bool = false
    ) {
      self.publisher = publisher
      self.publishedYear = publishedYear
      self.language = language
      self.durationText = durationText
      self.size = size
      self.hasAudio = hasAudio
      self.isEbook = isEbook
    }
  }
}
