import Foundation

nonisolated enum ChapterNumber {
  private static let tokensSearched = 4

  private static let words: [String: Int] = [
    "one": 1, "first": 1, "two": 2, "second": 2, "three": 3, "third": 3,
    "four": 4, "fourth": 4, "five": 5, "fifth": 5, "six": 6, "sixth": 6,
    "seven": 7, "seventh": 7, "eight": 8, "eighth": 8, "nine": 9, "ninth": 9,
    "ten": 10, "tenth": 10, "eleven": 11, "eleventh": 11, "twelve": 12, "twelfth": 12,
    "thirteen": 13, "thirteenth": 13, "fourteen": 14, "fourteenth": 14,
    "fifteen": 15, "fifteenth": 15, "sixteen": 16, "sixteenth": 16,
    "seventeen": 17, "seventeenth": 17, "eighteen": 18, "eighteenth": 18,
    "nineteen": 19, "nineteenth": 19, "twenty": 20, "twentieth": 20,
    "thirty": 30, "thirtieth": 30, "forty": 40, "fortieth": 40,
    "fifty": 50, "fiftieth": 50, "sixty": 60, "sixtieth": 60,
    "seventy": 70, "seventieth": 70, "eighty": 80, "eightieth": 80,
    "ninety": 90, "ninetieth": 90,
  ]

  private static let romanValues: [Character: Int] = [
    "i": 1, "v": 5, "x": 10, "l": 50, "c": 100, "d": 500, "m": 1000,
  ]

  static func parse(_ title: String) -> Int? {
    let tokens: [String] = title.split(separator: " ").map { String($0) }
    let searched = tokens.prefix(tokensSearched)

    for token in searched {
      if let digits = Int(token) { return digits }
    }

    if let spelled = spelled(in: Array(searched)) { return spelled }

    for token in searched {
      if let roman = roman(token) { return roman }
    }

    return nil
  }

  private static func spelled(in tokens: [String]) -> Int? {
    var total = 0
    var found = false

    for token in tokens {
      if token == "hundred", found {
        total = max(1, total) * 100
        continue
      }
      guard let value = words[token] else {
        if found { break }
        continue
      }
      total += value
      found = true
    }

    return found ? total : nil
  }

  private static func roman(_ token: String) -> Int? {
    guard !token.isEmpty, token.allSatisfy({ romanValues[$0] != nil }) else { return nil }

    var total = 0
    var previous = 0
    for character in token.reversed() {
      guard let value = romanValues[character] else { return nil }
      total += value < previous ? -value : value
      previous = max(previous, value)
    }

    guard total > 0, string(from: total) == token else { return nil }
    return total
  }

  private static func string(from number: Int) -> String {
    let numerals: [(Int, String)] = [
      (1000, "m"), (900, "cm"), (500, "d"), (400, "cd"), (100, "c"), (90, "xc"),
      (50, "l"), (40, "xl"), (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i"),
    ]

    var remaining = number
    var result = ""
    for (value, numeral) in numerals {
      while remaining >= value {
        result += numeral
        remaining -= value
      }
    }
    return result
  }
}
