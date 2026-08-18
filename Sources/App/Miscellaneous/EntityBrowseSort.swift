import Vapor

/// Sort order for the publisher/studio/person/license browse pages' name/title dropdown, next to
/// the search field. `created`/`updated` sort isn't offered yet - catalog-api's jsonapi
/// responses don't expose those timestamps (google/jsonapi skips embedded struct fields with no
/// tag of their own, so `AuditableVO`'s `created_at`/`updated_at` never reach the wire) - so
/// there's nothing to sort by until that's fixed upstream.
enum BrowseSortOrder: String {
  case asc, desc
}

func resolveBrowseSortOrder(_ raw: String?) -> BrowseSortOrder {
  BrowseSortOrder(rawValue: raw ?? "") ?? .asc
}

/// Sorts by `name`, case-insensitively, then reverses for `.desc` - a single stable pass rather
/// than a separate descending comparator, so ties break the same way in both directions.
func sortByName<T>(_ items: [T], order: BrowseSortOrder, name: (T) -> String) -> [T] {
  let sorted = items.sorted {
    name($0).localizedCaseInsensitiveCompare(name($1)) == .orderedAscending
  }
  return order == .asc ? sorted : sorted.reversed()
}
