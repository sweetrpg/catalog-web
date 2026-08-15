import CatalogAPIClient
import Foundation
import Vapor

/// Browse, detail, and edit pages for publishers, studios, persons, and licenses - the four
/// catalog entity types that, unlike volumes, previously had no pages of their own. One
/// controller for all four types (rather than four near-identical controllers) since their
/// page logic (fetch list, fetch one + its volumes, patch, review) is close to identical - see
/// design.md's "one parameterized controller" decision. Leaf templates stay one file per type
/// (`Resources/Views/<type>/...`), since the four types' attribute sets differ enough that a
/// shared template would need as much per-type conditional logic as separate ones.
struct VolumesController: RouteCollection {
  func boot(routes: RoutesBuilder) throws {

  }

  private struct BrowseQuery: Content {
    let q: String?
  }

  /// Case-insensitive substring match against `nameOf` a browse page's search query - the same
  /// in-memory filtering the existing volume browse page uses (these collections are small
  /// enough that no dedicated search endpoint is needed).
  private func filterByName<T>(_ items: [T], query: String?, nameOf: (T) -> String) -> [T] {
    guard let q = query, !q.isEmpty else { return items }
    let needle = q.lowercased()
    return items.filter { nameOf($0).lowercased().contains(needle) }
  }
}
