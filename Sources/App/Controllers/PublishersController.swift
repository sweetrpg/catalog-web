import CatalogAPIClient
import Foundation
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
    routes.get("publishers", ":id", use: detailPublisher)
    routes.get("publishers", ":id", "edit", use: editPublisherForm)
    routes.post("publishers", ":id", "edit", use: submitPublisherEdit)
    routes.post(
      "publishers", ":id", "proposed-changes", ":proposalID", "accept",
      use: acceptPublisherProposal)
    routes.post(
      "publishers", ":id", "proposed-changes", ":proposalID", "reject",
      use: rejectPublisherProposal)
  }

  private struct BrowseQuery: Content {
    let q: String?
  }

  @Sendable
  func browsePublishers(req: Request) async throws -> View {
    let query = try req.query.decode(BrowseQuery.self)
    let publishers = try await req.catalogAPI.fetchPublishers()
    let filtered = filterByName(publishers, query: query.q) { $0.name }

    return try await req.view.render(
      "publishers/browse",
      EntityBrowseContext(
        query: query.q ?? "",
        items: filtered.map { LeafPublisherCard($0) },
        noResults: filtered.isEmpty,
        user: (await req.currentUser).map(LeafUser.init),
        meta: await PageMeta.make(req)
      ))
  }

  @Sendable
  func detailPublisher(req: Request) async throws -> View {
    guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
    guard var publisher = try await req.catalogAPI.fetchPublisher(id: id) else {
      throw Abort(.notFound)
    }
    publisher.volumes = try await req.catalogAPI.fetchPublisherVolumes(id: id)
    let sessionUser = await req.currentUser
    let review = await buildReview(
      req: req, path: "/publishers", recordID: id, fieldSpecs: publisherFields,
      sessionUser: sessionUser)

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

  @Sendable
  func editPublisherForm(req: Request) async throws -> View {
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

  @Sendable
  func submitPublisherEdit(req: Request) async throws -> Response {
    try await submitEdit(req: req, path: "/publishers", fields: publisherFields)
  }

  @Sendable
  func acceptPublisherProposal(req: Request) async throws -> Response {
    try await acceptProposal(req: req, path: "/publishers")
  }

  @Sendable
  func rejectPublisherProposal(req: Request) async throws -> Response {
    try await rejectProposal(req: req, path: "/publishers")
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
