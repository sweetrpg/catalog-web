import CatalogAPIClient
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
  var credits: [(personId: String, role: String, person: String)] = []
  var reviews: [(author: String, rating: Int, text: String)] = []
  var properties: [(name: String, value: String)] = []
  /// Empty when unset. Editor/admin-only to set (see `volume-format-selector`'s spec) - always
  /// readable here regardless of viewer role, since catalog-api's `GET /volumes` doesn't gate
  /// this field the way `GET /vocabularies/format` gates the *candidate list*.
  var format: String = ""
  /// The volume's live sample-image ids (e.g. `["vol-1-0", "vol-1-1"]`) - empty until a session
  /// with staged samples has been finalized at least once (see `volume-sample-pages`'s spec).
  var sampleAssetIds: [String] = []
  var publisherRefs: [EntityRef] = []
  var studioRefs: [EntityRef] = []
  var licenseRefs: [EntityRef] = []

  var tagChips: [String] { Array(tags.prefix(3)) }
  /// Relative path (join with `meta.assetsURL`) to this volume's cover image on
  /// assets-web's dedicated `cover` asset kind (see the `expand-volume-detail-page` OpenSpec
  /// change). Most volumes have no file stored yet, so templates render this optimistically and
  /// let `onerror` reveal the existing "Cover pending" fallback on a 404 (or a 400, while
  /// assets-web's `cover` kind hasn't deployed yet - `onerror` fires on any non-2xx image
  /// response, so the fallback still degrades correctly either way).
  var coverAssetPath: String { "asset/cover/\(id)" }
  /// Relative paths to this volume's live sample images, same `asset/<kind>/<id>` shape as
  /// `coverAssetPath`.
  var samplePaths: [String] { sampleAssetIds.map { "asset/sample/\($0)" } }
}

/// A volume's id+title, as much as an entity detail page's associated-volumes list needs -
/// distinct from `VolumeViewModel`, which carries a full volume's own detail-page data.
struct VolumeSummary {
  let id: String
  let title: String
}
