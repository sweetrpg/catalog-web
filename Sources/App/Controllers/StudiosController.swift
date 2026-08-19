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
    routes.get("studios", "new", use: newStudioForm)
    routes.post("studios", "new", use: submitStudioCreate)
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
          canEdit: canEdit((await req.currentUser)?.roles ?? []),
          user: (await req.currentUser).map(LeafUser.init),
          meta: await PageMeta.make(req)
        ))
    }
  }

  @Sendable
  func newStudioForm(req: Request) async throws -> View {
    try await withSpan("studios-new-form") { _ in
      guard let user = await req.currentUser, canEdit(user.roles) else { throw Abort(.forbidden) }
      return try await req.view.render(
        "studios/create",
        makeCreateContext(
          basePath: "/studios", fields: studioFields, user: user, meta: await PageMeta.make(req)))
    }
  }

  @Sendable
  func submitStudioCreate(req: Request) async throws -> Response {
    try await submitCreate(req: req, path: "/studios", fields: studioFields)
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
      guard var studio = try await req.catalogAPI.fetchStudio(id: id) else {
        throw Abort(.notFound)
      }
      studio.volumes = try await req.catalogAPI.fetchStudioVolumes(id: id)
      let allVolumes = try await req.catalogAPI.fetchVolumes().map { ($0.id, $0.title) }

      let base = makeEditContext(
        id: id, basePath: "/studios", fields: studioFields,
        values: fieldValues(studio), user: user, meta: await PageMeta.make(req))

      return try await req.view.render(
        "studios/edit",
        EntityEditWithVolumesContext(
          base: base, canManageVolumes: canReview(user.roles), selectedVolumes: studio.volumes,
          allVolumes: allVolumes))
    }
  }

  @Sendable
  func submitStudioEdit(req: Request) async throws -> Response {
    try await withSpan("submit-studio-edit") { _ in
      guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
      guard let user = await req.currentUser, canEdit(user.roles) else { throw Abort(.forbidden) }

      let input = try req.content.decode([String: String].self)
      let known = Set(studioFields.map(\.key))
      let filtered = input.filter { known.contains($0.key) }

      let result = try await req.catalogAPI.patchEntity(
        path: "/studios", id: id, token: user.accessToken, fields: filtered)

      // Volume association is editor/admin-direct (no review workflow, see
      // sweetrpg/catalog-api#220) - a submitter's session never renders the volumes picker
      // (canEdit gates the whole page, but only editor/admin get review rights), so this simply
      // does nothing when the field is absent from the submission. Mirrors LicensesController's
      // submitLicenseEdit.
      if let volumeIdsRaw = input["volumeIds"] {
        let volumeIds = volumeIdsRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty }
        if canReview(user.roles) {
          try await req.catalogAPI.patchEntityVolumes(
            path: "/studios", id: id, token: user.accessToken, volumeIds: volumeIds)
        }
      }

      let basePath = "\(req.basePath)/studios/\(id)"
      switch result {
      case .applied:
        await req.catalogAPI.invalidateEntityListCache(path: "/studios")
        return req.redirect(to: basePath)
      case .proposed:
        return req.redirect(to: "\(basePath)?proposed=1")
      }
    }
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
