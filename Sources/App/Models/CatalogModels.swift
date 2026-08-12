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
  var publisherIds: [String] = []
  let studioNames: [String]
  var studioIds: [String] = []
  let licenseNames: [String]
  var credits: [(role: String, person: String)] = []
  var reviews: [(author: String, rating: Int, text: String)] = []

  var tagChips: [String] { Array(tags.prefix(3)) }
  /// Relative path (join with `meta.sharedAssetsURL`) to this volume's cover image on
  /// assets-web's dedicated `cover` asset kind (see the `expand-volume-detail-page` OpenSpec
  /// change). Most volumes have no file stored yet, so templates render this optimistically and
  /// let `onerror` reveal the existing "Cover pending" fallback on a 404 (or a 400, while
  /// assets-web's `cover` kind hasn't deployed yet - `onerror` fires on any non-2xx image
  /// response, so the fallback still degrades correctly either way).
  var coverAssetPath: String { "asset/cover/\(id).svg" }
}
