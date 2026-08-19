import CatalogAPIClient
import Crypto
import Foundation
import Tracing
import Vapor

/// Home, Browse, and Volume Detail - the three catalog-browsing pages, all backed by
/// catalog-api. Grouped in one controller since they share the same volume-fetching path,
/// unlike ShelvesController, which has its own concern.
struct CatalogController: RouteCollection {
  func boot(routes: RoutesBuilder) throws {
    routes.get(use: home)
    routes.get("browse", use: browse)
  }

  @Sendable
  func home(req: Request) async throws -> View {
    try await withSpan("home") { _ in
      let volumes = try await req.catalogAPI.fetchVolumes()
      let trending = Array(volumes.prefix(8))
      let tagCloud = Array(Set(volumes.flatMap(\.tags))).sorted().prefix(14)
      let stats = try await req.catalogAPI.fetchCatalogStats()

      return try await req.view.render(
        "home",
        HomeContext(
          volumeCount: stats.volumeCount,
          lastUpdated: stats.lastUpdated.map(Self.formatLastUpdated) ?? "Unknown",
          trending: trending.map(LeafVolumeCard.init),
          tagCloud: tagCloud.map { LeafTag(name: $0) },
          user: (await req.currentUser).map(LeafUser.init),
          meta: await PageMeta.make(req)
        ))
    }
  }

  private static func formatLastUpdated(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter.string(from: date)
  }

  @Sendable
  func browse(req: Request) async throws -> View {
    try await withSpan("browse") { _ in
      struct Query: Content {
        let q: String?
        let tag: String?
      }
      let query = try req.query.decode(Query.self)
      let volumes = try await req.catalogAPI.fetchVolumes()
      let tagCloud = Array(Set(volumes.flatMap(\.tags))).sorted().prefix(14)

      let filtered = volumes.filter { volume in
        if let tag = query.tag, !tag.isEmpty, !volume.tags.contains(tag) { return false }
        guard let q = query.q, !q.isEmpty else { return true }
        let needle = q.lowercased()
        return volume.title.lowercased().contains(needle)
          || volume.description.lowercased().contains(needle)
          || volume.tags.contains { $0.lowercased().contains(needle) }
      }

      return try await req.view.render(
        "browse",
        BrowseContext(
          query: query.q ?? "",
          noActiveTag: query.tag == nil || query.tag!.isEmpty,
          tagCloud: tagCloud.map { LeafTag(name: $0, isActive: $0 == query.tag) },
          volumes: filtered.map(LeafVolumeCard.init),
          noResults: filtered.isEmpty,
          user: (await req.currentUser).map(LeafUser.init),
          meta: await PageMeta.make(req)
        ))
    }
  }
}
