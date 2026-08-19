import LingoVapor
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

/// Pluralized "N volume(s)" label for a browse card, shared across every entity type that shows
/// a per-item volume count (licenses, publishers, ...).
func volumeCountLabel(_ count: Int, req: Request) async throws -> String {
  let lingo = try req.application.lingoVapor.lingo()
  // lingo.defaultLocale, not req.locale (LingoVapor's own property) - that reads
  // session.data, and this app deliberately never registers SessionsMiddleware (see
  // configure.swift). Vapor's session getter only assertionFailure()s on a missing
  // middleware, which release builds strip - masking it in production while still crashing
  // any debug-configuration run (tests, local `swift run` without -c release).
  return lingo.localize(
    "catalog.volume_count", locale: lingo.defaultLocale, interpolations: ["count": count])
}

/// Display label for a normalized property key (lowercase, spaces already turned into dashes -
/// see `normalizePropertyKey`). Prefers a `catalog.property.<key>` localization if one exists;
/// Lingo has no "does this key exist" check of its own, so a miss is detected the way Lingo's
/// own `localize` documents it: on a missing key it returns the key string unchanged. Falls back
/// to humanizing the raw key (dashes back to spaces, each word capitalized) for anything not
/// worth a dedicated translation.
func propertyDisplayLabel(_ key: String, req: Request) throws -> String {
  let lingo = try req.application.lingoVapor.lingo()
  let localizationKey = "catalog.property.\(key)"
  let localized = lingo.localize(localizationKey, locale: lingo.defaultLocale)
  if localized != localizationKey {
    return localized
  }
  return key.split(separator: "-")
    .map { $0.isEmpty ? "" : $0.prefix(1).uppercased() + $0.dropFirst() }
    .joined(separator: " ")
}

/// Normalizes user-entered property-key text (e.g. "Page Count", "ISBN 13") to the storage form
/// every property key is kept in: lowercase, spaces collapsed to single dashes. Display always
/// goes back through `propertyDisplayLabel`, never the raw stored key.
func normalizePropertyKey(_ raw: String) -> String {
  raw.trimmingCharacters(in: .whitespacesAndNewlines)
    .lowercased()
    .split(separator: " ", omittingEmptySubsequences: true)
    .joined(separator: "-")
}
