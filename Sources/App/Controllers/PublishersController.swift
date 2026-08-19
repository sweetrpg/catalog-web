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
  }

  private struct BrowseQuery: Content {
    let q: String?
    let order: String?
  }

  @Sendable
  func browsePublishers(req: Request) async throws -> View {
    try await withSpan("publishers-browse") { _ in
      let query = try req.query.decode(BrowseQuery.self)
      let order = resolveBrowseSortOrder(query.order)
      let publishers = try await req.catalogAPI.fetchPublishers()
      let filtered = filterByName(publishers, query: query.q) { $0.name }
      let sorted = sortByName(filtered, order: order) { $0.name }

      // Publishers are a small, fixed-ish collection (same assumption filterByName already
      // relies on) - a per-card volume-count fetch is fine here, matching licenses' browse page.
      var cards: [LeafPublisherCard] = []
      for publisher in sorted {
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

      return try await req.view.render(
        "publishers/detail",
        EntityDetailContext(
          publisher: LeafPublisherDetail(publisher),
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
  func editPublisherForm(req: Request) async throws -> View {
    try await withSpan("publishers-edit") { _ in
      guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
      guard let user = await req.currentUser, canEdit(user.roles) else { throw Abort(.forbidden) }
      guard let publisher = try await req.catalogAPI.fetchPublisher(id: id) else {
        throw Abort(.notFound)
      }

      return try await req.view.render(
        "publishers/edit",
        makeEditContext(
          id: id, basePath: "/publishers", fields: publisherFields,
          values: fieldValues(publisher), user: user, meta: await PageMeta.make(req)))
    }
  }

  @Sendable
  func submitPublisherEdit(req: Request) async throws -> Response {
    try await submitEdit(req: req, path: "/publishers", fields: publisherFields)
  }

  @Sendable
  func acceptPublisherVersion(req: Request) async throws -> Response {
    try await acceptVersionReview(req: req, path: "/publishers")
  }

  @Sendable
  func rejectPublisherVersion(req: Request) async throws -> Response {
    try await rejectVersionReview(req: req, path: "/publishers")
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
