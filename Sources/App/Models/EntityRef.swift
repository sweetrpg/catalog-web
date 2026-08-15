import CatalogAPIClient
import Foundation

/// An id+name pair for a related record - carries enough to both display a name and link to
/// that record's own detail page (`catalog-entity-detail`'s "volume links to its associated
/// entities" requirement), unlike a plain `[String]` of names.
struct EntityRef {
  let id: String
  let name: String
}
