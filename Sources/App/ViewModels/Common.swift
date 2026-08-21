import CatalogAPIClient
import Crypto
import Foundation
import Vapor

/// One free-form name/value property on a volume's detail page. `name` is always the raw,
/// normalized storage key (lowercase, dashes) - `displayLabel` is what templates render, via
/// `propertyDisplayLabel` (a localization if one exists for `name`, otherwise a humanized form).
struct LeafProperty: Content {
  let name: String
  let value: String
  let displayLabel: String
}

struct LeafEntityRef: Content {
  let id: String
  let name: String
  let isDeleted: Bool

  init(_ ref: EntityRef) {
    self.id = ref.id
    self.name = ref.name
    self.isDeleted = ref.isDeleted
  }
}

/// Flat, Leaf-friendly wrappers around the domain models above. Kept separate from
/// `VolumeViewModel` etc. so the API-facing models don't accumulate template-only convenience
/// properties (`ratingStars`, `hasX` booleans) that have nothing to do with fetching data.

struct LeafTag: Content {
  let name: String
  var isActive: Bool = false
}
