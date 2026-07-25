import Foundation

struct TagAttributes: Codable, Sendable {
  let name: String?
  let value: String?

  var displayName: String { name ?? value ?? "" }
}

struct VolumeAttributes: Codable, Sendable {
  let title: String?
  let description: String?
  let notes: String?
  let tags: [TagAttributes]?
}

struct NamedAttributes: Codable, Sendable {
  let name: String?
  let title: String?

  var displayName: String { name ?? title ?? "Untitled" }
}

struct PersonAttributes: Codable, Sendable {
  let name: String?
  let fullName: String?
  let firstName: String?
  let lastName: String?

  var displayName: String {
    if let name { return name }
    if let fullName { return fullName }
    return [firstName, lastName].compactMap { $0 }.joined(separator: " ").isEmpty
      ? "Unknown" : [firstName, lastName].compactMap { $0 }.joined(separator: " ")
  }
}

struct ContributionAttributes: Codable, Sendable {
  let role: String?
  let credit: String?
  let title: String?
}

struct ReviewAttributes: Codable, Sendable {
  let authorName: String?
  let author: String?
  let name: String?
  let rating: Double?
  let score: Double?
  let body: String?
  let text: String?
  let review: String?
  let content: String?

  var displayAuthor: String { authorName ?? author ?? name ?? "A reader" }
  var displayRating: Double { rating ?? score ?? 0 }
  var displayText: String { body ?? text ?? review ?? content ?? "" }
}

/// Flattened, view-ready representation of a Volume plus whatever related names/credits/reviews
/// have been resolved for it. Controllers assemble this from the raw JSON:API responses so Leaf
/// templates work with plain values, not relationship graphs.
struct VolumeViewModel {
  let id: String
  let title: String
  let description: String
  let notes: String
  let tags: [String]
  let systemNames: [String]
  let publisherNames: [String]
  let studioNames: [String]
  let licenseNames: [String]
  var credits: [(role: String, person: String)] = []
  var reviews: [(author: String, rating: Int, text: String)] = []

  var tagChips: [String] { Array(tags.prefix(3)) }
  var metaLine: String {
    var parts: [String] = []
    parts.append(contentsOf: systemNames.map { "System: \($0)" })
    parts.append(contentsOf: publisherNames.map { "Publisher: \($0)" })
    parts.append(contentsOf: studioNames.map { "Studio: \($0)" })
    return parts.joined(separator: " \u{b7} ")
  }
}
