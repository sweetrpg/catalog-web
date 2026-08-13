import CatalogAPIClient
import Foundation

/// An id+name pair for a related record - carries enough to both display a name and link to
/// that record's own detail page (`catalog-entity-detail`'s "volume links to its associated
/// entities" requirement), unlike a plain `[String]` of names.
struct EntityRef {
  let id: String
  let name: String
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
  var publisherRefs: [EntityRef] = []
  var studioRefs: [EntityRef] = []
  var licenseRefs: [EntityRef] = []

  var tagChips: [String] { Array(tags.prefix(3)) }
  /// Relative path (join with `meta.sharedAssetsURL`) to this volume's cover image on
  /// assets-web's dedicated `cover` asset kind (see the `expand-volume-detail-page` OpenSpec
  /// change). Most volumes have no file stored yet, so templates render this optimistically and
  /// let `onerror` reveal the existing "Cover pending" fallback on a 404 (or a 400, while
  /// assets-web's `cover` kind hasn't deployed yet - `onerror` fires on any non-2xx image
  /// response, so the fallback still degrades correctly either way).
  var coverAssetPath: String { "asset/cover/\(id).svg" }
}

/// A volume's id+title, as much as an entity detail page's associated-volumes list needs -
/// distinct from `VolumeViewModel`, which carries a full volume's own detail-page data.
struct VolumeSummary {
  let id: String
  let title: String
}

struct PublisherViewModel {
  let id: String
  let name: String
  let address: String
  let website: String
  let notes: String
  let tags: [String]
  var volumes: [VolumeSummary] = []

  init(id: String, attributes: PublisherAttributes) {
    self.id = id
    self.name = attributes.name ?? "Untitled"
    self.address = attributes.address ?? ""
    self.website = attributes.website ?? ""
    self.notes = attributes.notes ?? ""
    self.tags = (attributes.tags ?? []).map(\.displayName).filter { !$0.isEmpty }
  }
}

struct StudioViewModel {
  let id: String
  let name: String
  let website: String
  let notes: String
  let tags: [String]
  var volumes: [VolumeSummary] = []

  init(id: String, attributes: StudioAttributes) {
    self.id = id
    self.name = attributes.name ?? "Untitled"
    self.website = attributes.website ?? ""
    self.notes = attributes.notes ?? ""
    self.tags = (attributes.tags ?? []).map(\.displayName).filter { !$0.isEmpty }
  }
}

struct PersonViewModel {
  let id: String
  let name: String
  let notes: String
  let tags: [String]
  var volumes: [VolumeSummary] = []

  init(id: String, attributes: PersonAttributes) {
    self.id = id
    self.name = attributes.displayName
    self.notes = attributes.notes ?? ""
    self.tags = (attributes.tags ?? []).map(\.displayName).filter { !$0.isEmpty }
  }
}

struct LicenseViewModel {
  let id: String
  let title: String
  let shortTitle: String
  let version: String
  let deed: String
  let legalCode: String
  let website: String
  let status: String
  let availability: String
  let notes: String
  let tags: [String]
  var volumes: [VolumeSummary] = []

  init(id: String, attributes: LicenseAttributes) {
    self.id = id
    self.title = attributes.title ?? "Untitled"
    self.shortTitle = attributes.shortTitle ?? ""
    self.version = attributes.version ?? ""
    self.deed = attributes.deed ?? ""
    self.legalCode = attributes.legalCode ?? ""
    self.website = attributes.website ?? ""
    self.status = attributes.status ?? ""
    self.availability = attributes.availability ?? ""
    self.notes = attributes.notes ?? ""
    self.tags = (attributes.tags ?? []).map(\.displayName).filter { !$0.isEmpty }
  }
}
