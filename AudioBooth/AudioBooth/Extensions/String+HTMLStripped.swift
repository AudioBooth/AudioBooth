import Foundation

extension String {
  var htmlStripped: String {
    var text = replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)

    text = text.replacing(#/&#(x?)([0-9a-fA-F]+);/#) { match in
      let radix = match.1.isEmpty ? 10 : 16
      guard let code = UInt32(match.2, radix: radix), let scalar = Unicode.Scalar(code) else {
        return String(match.0)
      }
      return String(Character(scalar))
    }

    let entities = [
      ("&nbsp;", " "),
      ("&quot;", "\""),
      ("&apos;", "'"),
      ("&lt;", "<"),
      ("&gt;", ">"),
      ("&amp;", "&"),
    ]
    for (entity, character) in entities {
      text = text.replacingOccurrences(of: entity, with: character)
    }

    return
      text
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
