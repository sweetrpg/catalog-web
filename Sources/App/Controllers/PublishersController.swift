import CatalogAPIClient
import Foundation
import Tracing
import Vapor

let publisherFields: [EntityFieldSpec] = [
  EntityFieldSpec(key: "name", label: "Name"),
  EntityFieldSpec(key: "address", label: "Address"),
  EntityFieldSpec(key: "website", label: "Website"),
  EntityFieldSpec(key: "notes", label: "Notes"),
]

func fieldValues(_ p: PublisherViewModel) -> [String: String] {
  ["name": p.name, "address": p.address, "website": p.website, "notes": p.notes]
}

/// Version-attributes counterpart of the `fieldValues` overload above - used to build the
/// review diff table's "proposed value" column against a submitted version's own field values,
/// the same way `fieldValues(_ p: PublisherViewModel)` supplies the "live value" column.
func fieldValues(_ p: PublisherVersionAttributes) -> [String: String] {
  ["name": p.name, "address": p.address, "notes": p.notes]
}

/// Browse, detail, and edit pages for publishers, studios, persons, and licenses - the four
/// catalog entity types that, unlike volumes, previously had no pages of their own. One
/// controller for all four types (rather than four near-identical controllers) since their
/// page logic (fetch list, fetch one + its volumes, patch, review) is close to identical - see
/// design.md's "one parameterized controller" decision. Leaf templates stay one file per type
/// (`Resources/Views/<type>/...`), since the four types' attribute sets differ enough that a
/// shared template would need as much per-type conditional logic as separate ones.
struct PublishersController: RouteCollection {
  func boot(routes: RoutesBuilder) throws {
    routes.get("publishers", use: browsePublishers)
    routes.get("publishers", "new", use: newPublisherForm)
    routes.post("publishers", "new", use: submitPublisherCreate)
    routes.get("publishers", ":id", use: detailPublisher)
    routes.get("publishers", ":id", "edit", use: editPublisherForm)
    routes.post("publishers", ":id", "edit", use: submitPublisherEdit)
    routes.post(
      "publishers", ":id", "versions", ":version", "accept",
      use: acceptPublisherVersion)
    routes.post(
      "publishers", ":id", "versions", ":version", "reject",
      use: rejectPublisherVersion)
    routes.post("publishers", ":id", "delete", use: deletePublisher)
    routes.post("publishers", ":id", "undelete", use: restorePublisher)
  }

  private struct BrowseQuery: Content {
    let q: String?
    let order: String?
    let page: Int?
  }

  @Sendable
  func browsePublishers(req: Request) async throws -> View {
    try await withSpan("publishers-browse") { _ in
      let query = try req.query.decode(BrowseQuery.self)
      let order = resolveBrowseSortOrder(query.order)
      let publishers = try await req.catalogAPI.fetchPublishers()
      let filtered = filterByName(publishers, query: query.q) { $0.name }
      let sorted = sortByName(filtered, order: order) { $0.name }
      let (page, pagination) = paginate(
        sorted, page: query.page ?? 1, basePath: req.basePath, path: "/publishers",
        query: ["q": query.q ?? "", "order": query.order ?? ""])

      // A per-card volume-count fetch, only for the current page's items - pagination already
      // bounds this to at most browsePageSize requests instead of one per publisher in the
      // whole (possibly filtered) collection.
      var cards: [LeafPublisherCard] = []
      for publisher in page {
        let volumeCount =
          (try? await req.catalogAPI.fetchPublisherVolumes(id: publisher.id))?.count ?? 0
        let label = try await volumeCountLabel(volumeCount, req: req)
        cards.append(LeafPublisherCard(publisher, volumeCountLabel: label))
      }

      return try await req.view.render(
        "publishers/browse",
        EntityBrowseContext(
          query: query.q ?? "",
          items: cards,
          noResults: filtered.isEmpty,
          orderIsAsc: order == .asc,
          orderIsDesc: order == .desc,
          canEdit: canEdit((await req.currentUser)?.roles ?? []),
          pagination: pagination,
          user: (await req.currentUser).map(LeafUser.init),
          meta: await PageMeta.make(req)
        ))
    }
  }

  @Sendable
  func newPublisherForm(req: Request) async throws -> View {
    try await withSpan("publishers-new-form") { _ in
      guard let user = await req.currentUser, canEdit(user.roles) else { throw Abort(.forbidden) }
      return try await req.view.render(
        "publishers/create",
        makeCreateContext(
          basePath: "/publishers", fields: publisherFields, user: user,
          meta: await PageMeta.make(req)))
    }
  }

  @Sendable
  func submitPublisherCreate(req: Request) async throws -> Response {
    try await submitCreate(req: req, path: "/publishers", fields: publisherFields)
  }

  @Sendable
  func detailPublisher(req: Request) async throws -> View {
    try await withSpan("publishers-detail") { _ in
      guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
      guard var publisher = try await req.catalogAPI.fetchPublisher(id: id) else {
        throw Abort(.notFound)
      }
      publisher.volumes = try await req.catalogAPI.fetchPublisherVolumes(id: id)
      let sessionUser = await req.currentUser
      let review: LeafEntityVersionReview? = await buildReview(
        req: req, path: "/publishers", recordID: id, fieldSpecs: publisherFields,
        currentValues: fieldValues(publisher), sessionUser: sessionUser,
        versionFieldValues: { (v: PublisherVersionAttributes) in fieldValues(v) })
      let isDeleted = await req.catalogAPI.fetchIsDeleted(path: "/publishers/\(id)")

      return try await req.view.render(
        "publishers/detail",
        EntityDetailContext(
          publisher: LeafPublisherDetail(publisher),
          canEdit: canEdit(sessionUser?.roles ?? []),
          canDelete: canDelete(sessionUser?.roles ?? []),
          isDeleted: isDeleted,
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
  func editPublisherForm(req: Request) async throws -> View {
    try await withSpan("publishers-edit") { _ in
      guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
      guard let user = await req.currentUser, canEdit(user.roles) else { throw Abort(.forbidden) }
      guard var publisher = try await req.catalogAPI.fetchPublisher(id: id) else {
        throw Abort(.notFound)
      }
      publisher.volumes = try await req.catalogAPI.fetchPublisherVolumes(id: id)
      let allVolumes = try await req.catalogAPI.fetchVolumes().map { ($0.id, $0.title) }

      let base = makeEditContext(
        id: id, basePath: "/publishers", fields: publisherFields,
        values: fieldValues(publisher), user: user, meta: await PageMeta.make(req))

      return try await req.view.render(
        "publishers/edit",
        EntityEditWithVolumesContext(
          base: base, canManageVolumes: canReview(user.roles), selectedVolumes: publisher.volumes,
          allVolumes: allVolumes))
    }
  }

  @Sendable
  func submitPublisherEdit(req: Request) async throws -> Response {
    try await withSpan("submit-publisher-edit") { _ in
      guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
      guard let user = await req.currentUser, canEdit(user.roles) else { throw Abort(.forbidden) }

      let input = try req.content.decode([String: String].self)
      let known = Set(publisherFields.map(\.key))
      let filtered = input.filter { known.contains($0.key) }

      let result = try await req.catalogAPI.patchEntity(
        path: "/publishers", id: id, token: user.accessToken, fields: filtered)

      // Volume association is editor/admin-direct (no review workflow, see
      // sweetrpg/catalog-api#220) - mirrors StudiosController.submitStudioEdit/
      // LicensesController.submitLicenseEdit.
      if let volumeIdsRaw = input["volumeIds"] {
        let volumeIds = volumeIdsRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty }
        if canReview(user.roles) {
          try await req.catalogAPI.patchEntityVolumes(
            path: "/publishers", id: id, token: user.accessToken, volumeIds: volumeIds)
        }
      }

      let basePath = "\(req.basePath)/publishers/\(id)"
      switch result {
      case .applied:
        await req.catalogAPI.invalidateEntityListCache(path: "/publishers")
        return req.redirect(to: basePath)
      case .proposed:
        return req.redirect(to: "\(basePath)?proposed=1")
      }
    }
  }

  @Sendable
  func acceptPublisherVersion(req: Request) async throws -> Response {
    try await acceptVersionReview(req: req, path: "/publishers")
  }

  @Sendable
  func rejectPublisherVersion(req: Request) async throws -> Response {
    try await rejectVersionReview(req: req, path: "/publishers")
  }

  /// Soft-deletes a publisher - admin only, enforced both here and by catalog-api itself.
  @Sendable
  func deletePublisher(req: Request) async throws -> Response {
    try await withSpan("publisher-delete") { _ in
      guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
      guard let user = await req.currentUser, canDelete(user.roles) else {
        throw Abort(.forbidden)
      }
      try await req.catalogAPI.deleteEntity(path: "/publishers/\(id)", token: user.accessToken)
      await req.catalogAPI.invalidateListCache(path: "/publishers")
      return req.redirect(to: "\(req.basePath)/publishers/\(id)")
    }
  }

  /// Restores a soft-deleted publisher - admin only.
  @Sendable
  func restorePublisher(req: Request) async throws -> Response {
    try await withSpan("publisher-restore") { _ in
      guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
      guard let user = await req.currentUser, canDelete(user.roles) else {
        throw Abort(.forbidden)
      }
      try await req.catalogAPI.restoreEntity(path: "/publishers/\(id)", token: user.accessToken)
      await req.catalogAPI.invalidateListCache(path: "/publishers")
      return req.redirect(to: "\(req.basePath)/publishers/\(id)")
    }
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
