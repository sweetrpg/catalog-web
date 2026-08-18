import CatalogAPIClient
import Crypto
import Foundation
import Vapor

/// One free-form name/value property on a volume's detail page.
struct LeafProperty: Content {
  let name: String
  let value: String

  init(_ property: (name: String, value: String)) {
    self.name = property.name
    self.value = property.value
  }
}

struct LeafEntityRef: Content {
  let id: String
  let name: String

  init(_ ref: EntityRef) {
    self.id = ref.id
    self.name = ref.name
  }
}

/// Flat, Leaf-friendly wrappers around the domain models above. Kept separate from
/// `VolumeViewModel` etc. so the API-facing models don't accumulate template-only convenience
/// properties (`ratingStars`, `hasX` booleans) that have nothing to do with fetching data.

struct LeafTag: Content {
  let name: String
  var isActive: Bool = false
}
