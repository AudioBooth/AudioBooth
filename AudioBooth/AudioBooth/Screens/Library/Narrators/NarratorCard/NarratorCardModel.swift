import API
import Foundation

final class NarratorCardModel: NarratorCard.Model {
  init(narrator: Narrator) {
    super.init(
      id: narrator.id,
      name: narrator.name,
      bookCount: narrator.numBooks ?? 0,
      imageURL: narrator.imageURL
    )
  }
}
