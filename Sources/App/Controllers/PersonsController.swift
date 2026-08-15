import CatalogAPIClient
import Foundation
import Vapor

let personFields: [EntityFieldSpec] = [
  EntityFieldSpec(key: "name", label: "Name"),
  EntityFieldSpec(key: "notes", label: "Notes"),
]

func fieldValues(_ p: PersonViewModel) -> [String: String] {
  ["name": p.name, "notes": p.notes]
}

/// Browse, detail, and edit pages for publishers, studios, persons, and licenses - the four
/// catalog entity types that, unlike volumes, previously had no pages of their own. One
/// controller for all four types (rather than four near-identical controllers) since their
/// page logic (fetch list, fetch one + its volumes, patch, review) is close to identical - see
/// design.md's "one parameterized controller" decision. Leaf templates stay one file per type
/// (`Resources/Views/<type>/...`), since the four types' attribute sets differ enough that a
/// shared template would need as much per-type conditional logic as separate ones.
struct PersonsController: RouteCollection {
  func boot(routes: RoutesBuilder) throws {
    routes.get("persons", use: browsePersons)
    routes.get("persons", ":id", use: detailPerson)
    routes.get("persons", ":id", "edit", use: editPersonForm)
    routes.post("persons", ":id", "edit", use: submitPersonEdit)
    routes.post(
      "persons", ":id", "proposed-changes", ":proposalID", "accept", use: acceptPersonProposal)
    routes.post(
      "persons", ":id", "proposed-changes", ":proposalID", "reject", use: rejectPersonProposal)
  }

  private struct BrowseQuery: Content {
    let q: String?
  }

  @Sendable
  func browsePersons(req: Request) async throws -> View {
    let query = try req.query.decode(BrowseQuery.self)
    let persons = try await req.catalogAPI.fetchPersonsCatalog()
    let filtered = filterByName(persons, query: query.q) { $0.name }

    return try await req.view.render(
      "persons/browse",
      EntityBrowseContext(
        query: query.q ?? "",
        items: filtered.map { LeafPersonCard($0) },
        noResults: filtered.isEmpty,
        user: (await req.currentUser).map(LeafUser.init),
        meta: await PageMeta.make(req)
      ))
  }

  @Sendable
  func detailPerson(req: Request) async throws -> View {
    guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
    guard var person = try await req.catalogAPI.fetchPerson(id: id) else {
      throw Abort(.notFound)
    }
    person.volumes = try await req.catalogAPI.fetchPersonVolumes(id: id)
    let sessionUser = await req.currentUser
    let review = await buildReview(
      req: req, path: "/persons", recordID: id, fieldSpecs: personFields,
      sessionUser: sessionUser)

    return try await req.view.render(
      "persons/detail",
      EntityDetailContext(
        person: LeafPersonDetail(person),
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
  func editPersonForm(req: Request) async throws -> View {
    guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
    guard let user = await req.currentUser, canEdit(user.roles) else { throw Abort(.forbidden) }
    guard let person = try await req.catalogAPI.fetchPerson(id: id) else {
      throw Abort(.notFound)
    }
    return try await req.view.render(
      "persons/edit",
      makeEditContext(
        id: id, basePath: "/persons", fields: personFields,
        values: fieldValues(person), user: user, meta: await PageMeta.make(req)))
  }

  @Sendable
  func submitPersonEdit(req: Request) async throws -> Response {
    try await submitEdit(req: req, path: "/persons", fields: personFields)
  }

  @Sendable
  func acceptPersonProposal(req: Request) async throws -> Response {
    try await acceptProposal(req: req, path: "/persons")
  }

  @Sendable
  func rejectPersonProposal(req: Request) async throws -> Response {
    try await rejectProposal(req: req, path: "/persons")
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
