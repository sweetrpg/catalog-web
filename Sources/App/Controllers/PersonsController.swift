import CatalogAPIClient
import Foundation
import Tracing
import Vapor

let personFields: [EntityFieldSpec] = [
  EntityFieldSpec(key: "name", label: "Name"),
  EntityFieldSpec(key: "notes", label: "Notes"),
]

func fieldValues(_ p: PersonViewModel) -> [String: String] {
  ["name": p.name, "notes": p.notes]
}

func fieldValues(_ p: PersonVersionAttributes) -> [String: String] {
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
    routes.get("persons", "new", use: newPersonForm)
    routes.post("persons", "new", use: submitPersonCreate)
    routes.get("persons", "bulk-add", use: bulkAddPersonsForm)
    routes.post("persons", "bulk-add", use: submitBulkAddPersons)
    routes.get("persons", ":id", use: detailPerson)
    routes.get("persons", ":id", "edit", use: editPersonForm)
    routes.post("persons", ":id", "edit", use: submitPersonEdit)
    routes.post(
      "persons", ":id", "versions", ":version", "accept", use: acceptPersonVersion)
    routes.post(
      "persons", ":id", "versions", ":version", "reject", use: rejectPersonVersion)
  }

  private struct BrowseQuery: Content {
    let q: String?
    let order: String?
    // Set by submitBulkAddPersons' redirect - see PersonsBrowseContext's own doc comment for why
    // this rides on persons/browse rather than a separate results page.
    let bulk_created: Int?
    let bulk_failed: Int?
    let bulk_errors: String?
  }

  @Sendable
  func browsePersons(req: Request) async throws -> View {
    try await withSpan("persons-browse") { _ in
      let query = try req.query.decode(BrowseQuery.self)
      let order = resolveBrowseSortOrder(query.order)
      let persons = try await req.catalogAPI.fetchPersonsCatalog()
      let filtered = filterByName(persons, query: query.q) { $0.name }
      let sorted = sortByName(filtered, order: order) { $0.name }
      let roles = (await req.currentUser)?.roles ?? []

      var bulkFailures: [LeafBulkAddFailure] = []
      if let errorsJSON = query.bulk_errors, let data = errorsJSON.data(using: .utf8) {
        bulkFailures = (try? JSONDecoder().decode([LeafBulkAddFailure].self, from: data)) ?? []
      }

      return try await req.view.render(
        "persons/browse",
        PersonsBrowseContext(
          query: query.q ?? "",
          items: sorted.map { LeafPersonCard($0) },
          noResults: filtered.isEmpty,
          orderIsAsc: order == .asc,
          orderIsDesc: order == .desc,
          canEdit: canEdit(roles),
          canBulkAdd: canBulkAddPersons(roles),
          hasBulkResult: query.bulk_created != nil || query.bulk_failed != nil,
          bulkCreatedCount: query.bulk_created ?? 0,
          bulkFailedCount: query.bulk_failed ?? 0,
          bulkFailures: bulkFailures,
          user: (await req.currentUser).map(LeafUser.init),
          meta: await PageMeta.make(req)
        ))
    }
  }

  @Sendable
  func bulkAddPersonsForm(req: Request) async throws -> View {
    try await withSpan("persons-bulk-add-form") { _ in
      guard let user = await req.currentUser, canBulkAddPersons(user.roles) else {
        throw Abort(.forbidden)
      }
      return try await req.view.render(
        "persons/bulk-add",
        BulkAddPersonsContext(
          backPath: "/persons", submitPath: "/persons/bulk-add",
          user: LeafUser(user), meta: await PageMeta.make(req)))
    }
  }

  private struct BulkAddInput: Content {
    let names: String
  }

  @Sendable
  func submitBulkAddPersons(req: Request) async throws -> Response {
    try await withSpan("submit-bulk-add-persons") { _ in
      guard let user = await req.currentUser, canBulkAddPersons(user.roles) else {
        throw Abort(.forbidden)
      }

      let input = try req.content.decode(BulkAddInput.self)
      let names =
        input.names
        .split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }

      let results = try await req.catalogAPI.bulkCreatePersons(
        fields: names.map { ["name": $0] }, token: user.accessToken)

      let createdCount = results.filter(\.success).count
      let failures = zip(names, results).compactMap { name, result -> LeafBulkAddFailure? in
        guard !result.success else { return nil }
        return LeafBulkAddFailure(name: name, error: result.error ?? "unknown error")
      }

      if createdCount > 0 {
        await req.catalogAPI.invalidateEntityListCache(path: "/persons")
      }

      var components = URLComponents()
      components.queryItems = [
        URLQueryItem(name: "bulk_created", value: String(createdCount)),
        URLQueryItem(name: "bulk_failed", value: String(failures.count)),
      ]
      if !failures.isEmpty, let encoded = try? JSONEncoder().encode(failures),
        let json = String(data: encoded, encoding: .utf8)
      {
        components.queryItems?.append(URLQueryItem(name: "bulk_errors", value: json))
      }

      return req.redirect(to: "\(req.basePath)/persons?\(components.percentEncodedQuery ?? "")")
    }
  }

  @Sendable
  func newPersonForm(req: Request) async throws -> View {
    try await withSpan("persons-new-form") { _ in
      guard let user = await req.currentUser, canEdit(user.roles) else { throw Abort(.forbidden) }
      return try await req.view.render(
        "persons/create",
        makeCreateContext(
          basePath: "/persons", fields: personFields, user: user, meta: await PageMeta.make(req)))
    }
  }

  @Sendable
  func submitPersonCreate(req: Request) async throws -> Response {
    try await submitCreate(req: req, path: "/persons", fields: personFields)
  }

  @Sendable
  func detailPerson(req: Request) async throws -> View {
    try await withSpan("persons-detail") { _ in
      guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
      guard var person = try await req.catalogAPI.fetchPerson(id: id) else {
        throw Abort(.notFound)
      }
      person.volumes = try await req.catalogAPI.fetchPersonVolumes(id: id)
      let sessionUser = await req.currentUser
      let review: LeafEntityVersionReview? = await buildReview(
        req: req, path: "/persons", recordID: id, fieldSpecs: personFields,
        currentValues: fieldValues(person), sessionUser: sessionUser,
        versionFieldValues: { (v: PersonVersionAttributes) in fieldValues(v) })

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
  }

  @Sendable
  func editPersonForm(req: Request) async throws -> View {
    try await withSpan("persons-edit-form") { _ in
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
  }

  @Sendable
  func submitPersonEdit(req: Request) async throws -> Response {
    try await submitEdit(req: req, path: "/persons", fields: personFields)
  }

  @Sendable
  func acceptPersonVersion(req: Request) async throws -> Response {
    try await acceptVersionReview(req: req, path: "/persons")
  }

  @Sendable
  func rejectPersonVersion(req: Request) async throws -> Response {
    try await rejectVersionReview(req: req, path: "/persons")
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
