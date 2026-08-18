import CatalogAPIClient
import Foundation
import Tracing
import Vapor

let studioFields: [EntityFieldSpec] = [
  EntityFieldSpec(key: "name", label: "Name"),
  EntityFieldSpec(key: "website", label: "Website"),
  EntityFieldSpec(key: "notes", label: "Notes"),
]

func fieldValues(_ s: StudioViewModel) -> [String: String] {
  ["name": s.name, "website": s.website, "notes": s.notes]
}

func fieldValues(_ s: StudioVersionAttributes) -> [String: String] {
  ["name": s.name, "notes": s.notes]
}

/// Browse, detail, and edit pages for publishers, studios, persons, and licenses - the four
/// catalog entity types that, unlike volumes, previously had no pages of their own. One
/// controller for all four types (rather than four near-identical controllers) since their
/// page logic (fetch list, fetch one + its volumes, patch, review) is close to identical - see
/// design.md's "one parameterized controller" decision. Leaf templates stay one file per type
/// (`Resources/Views/<type>/...`), since the four types' attribute sets differ enough that a
/// shared template would need as much per-type conditional logic as separate ones.
struct StudiosController: RouteCollection {
  func boot(routes: RoutesBuilder) throws {
    routes.get("studios", use: browseStudios)
    routes.get("studios", ":id", use: detailStudio)
    routes.get("studios", ":id", "edit", use: editStudioForm)
    routes.post("studios", ":id", "edit", use: submitStudioEdit)
    routes.post(
      "studios", ":id", "versions", ":version", "accept", use: acceptStudioVersion)
    routes.post(
      "studios", ":id", "versions", ":version", "reject", use: rejectStudioVersion)
  }

  private struct BrowseQuery: Content {
    let q: String?
    let order: String?
  }

  @Sendable
  func browseStudios(req: Request) async throws -> View {
    try await withSpan("studios-browse") { _ in
      let query = try req.query.decode(BrowseQuery.self)
      let order = resolveBrowseSortOrder(query.order)
      let studios = try await req.catalogAPI.fetchStudios()
      let filtered = filterByName(studios, query: query.q) { $0.name }
      let sorted = sortByName(filtered, order: order) { $0.name }

      return try await req.view.render(
        "studios/browse",
        EntityBrowseContext(
          query: query.q ?? "",
          items: sorted.map { LeafStudioCard($0) },
          noResults: filtered.isEmpty,
          orderIsAsc: order == .asc,
          orderIsDesc: order == .desc,
          user: (await req.currentUser).map(LeafUser.init),
          meta: await PageMeta.make(req)
        ))
    }
  }

  @Sendable
  func detailStudio(req: Request) async throws -> View {
    try await withSpan("studios-detail") { _ in
      guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
      guard var studio = try await req.catalogAPI.fetchStudio(id: id) else {
        throw Abort(.notFound)
      }
      studio.volumes = try await req.catalogAPI.fetchStudioVolumes(id: id)
      let sessionUser = await req.currentUser
      let review: LeafEntityVersionReview? = await buildReview(
        req: req, path: "/studios", recordID: id, fieldSpecs: studioFields,
        currentValues: fieldValues(studio), sessionUser: sessionUser,
        versionFieldValues: { (v: StudioVersionAttributes) in fieldValues(v) })

      return try await req.view.render(
        "studios/detail",
        EntityDetailContext(
          studio: LeafStudioDetail(studio),
          canEdit: canEdit(sessionUser?.roles ?? []),
          justProposed: req.query[String.self, at: "proposed"] == "1",
          review: review,
          conflicts: (req.query[String.self, at: "conflicts"] ?? "")
            .split(separator: ",").map(String.init),
          user: sessionUser.map(LeafUser.init),
          meta: await PageMeta.make(req)
        ))
    }
  }

  @Sendable
  func editStudioForm(req: Request) async throws -> View {
    try await withSpan("studios-edit-form") { _ in
      guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
      guard let user = await req.currentUser, canEdit(user.roles) else { throw Abort(.forbidden) }
      guard let studio = try await req.catalogAPI.fetchStudio(id: id) else {
        throw Abort(.notFound)
      }

      return try await req.view.render(
        "studios/edit",
        makeEditContext(
          id: id, basePath: "/studios", fields: studioFields,
          values: fieldValues(studio), user: user, meta: await PageMeta.make(req)))
    }
  }

  @Sendable
  func submitStudioEdit(req: Request) async throws -> Response {
    try await submitEdit(req: req, path: "/studios", fields: studioFields)
  }

  @Sendable
  func acceptStudioVersion(req: Request) async throws -> Response {
    try await acceptVersionReview(req: req, path: "/studios")
  }

  @Sendable
  func rejectStudioVersion(req: Request) async throws -> Response {
    try await rejectVersionReview(req: req, path: "/studios")
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
