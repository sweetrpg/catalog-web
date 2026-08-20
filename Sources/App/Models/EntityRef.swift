import CatalogAPIClient
import Foundation

/// An id+name pair for a related record - carries enough to both display a name and link to
/// that record's own detail page (`catalog-entity-detail`'s "volume links to its associated
/// entities" requirement), unlike a plain `[String]` of names.
struct EntityRef {
  let id: String
  let name: String
  /// `true` when this reference was resolved via the unfiltered per-id fallback fetch because
  /// the referenced record no longer appears in the live (non-deleted) name map - see
  /// `CatalogAPIClientService.resolveDeletedReferences`. Lets a still-referenced-but-deleted
  /// entity render labeled ("Acme Press (deleted)") instead of silently vanishing.
  var isDeleted: Bool = false
}
