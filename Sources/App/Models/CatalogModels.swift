import Foundation

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
