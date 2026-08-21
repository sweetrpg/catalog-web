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
      let tagCloud = Array(Set(volumes.flatMap(\.tags))).sorted().prefix(14)
      let stats = try await req.catalogAPI.fetchCatalogStats()

      let statCards = [
        LeafTypeStatsCard(
          label: "Volumes", detailPathPrefix: "/volumes", browsePath: "/browse",
          stats: stats.volumes),
        LeafTypeStatsCard(
          label: "Publishers", detailPathPrefix: "/publishers", browsePath: "/publishers",
          stats: stats.publishers),
        LeafTypeStatsCard(
          label: "Studios", detailPathPrefix: "/studios", browsePath: "/studios",
          stats: stats.studios),
        LeafTypeStatsCard(
          label: "Persons", detailPathPrefix: "/persons", browsePath: "/persons",
          stats: stats.persons),
        LeafTypeStatsCard(
          label: "Licenses", detailPathPrefix: "/licenses", browsePath: "/licenses",
          stats: stats.licenses),
        // No /systems/:id page or /systems browse page exists in catalog-web today - nil
        // renders both as plain text instead of a dead link.
        LeafTypeStatsCard(
          label: "Systems", detailPathPrefix: nil, browsePath: nil, stats: stats.systems),
      ]

      return try await req.view.render(
        "home",
        HomeContext(
          statCards: statCards,
          tagCloud: tagCloud.map { LeafTag(name: $0) },
          user: (await req.currentUser).map(LeafUser.init),
          meta: await PageMeta.make(req)
        ))
    }
  }

  @Sendable
  func browse(req: Request) async throws -> View {
    try await withSpan("browse") { _ in
      struct Query: Content {
        let q: String?
        let tag: String?
        let page: Int?
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
      let (page, pagination) = paginate(
        filtered, page: query.page ?? 1, basePath: req.basePath, path: "/browse",
        query: ["q": query.q ?? "", "tag": query.tag ?? ""])

      return try await req.view.render(
        "browse",
        BrowseContext(
          query: query.q ?? "",
          noActiveTag: query.tag == nil || query.tag!.isEmpty,
          tagCloud: tagCloud.map { LeafTag(name: $0, isActive: $0 == query.tag) },
          volumes: page.map(LeafVolumeCard.init),
          noResults: filtered.isEmpty,
          pagination: pagination,
          user: (await req.currentUser).map(LeafUser.init),
          meta: await PageMeta.make(req)
        ))
    }
  }
}
