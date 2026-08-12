import CatalogAPIClient
import Foundation
import Vapor

/// One patchable field's key (matches catalog-api's PATCH field name) and display label -
/// mirrors CatalogController.swift's private `patchableFields` array, but declared per entity
/// type below instead of hardcoded to volume's three fields.
struct EntityFieldSpec {
  let key: String
  let label: String
}

let publisherFields: [EntityFieldSpec] = [
  EntityFieldSpec(key: "name", label: "Name"),
  EntityFieldSpec(key: "address", label: "Address"),
  EntityFieldSpec(key: "website", label: "Website"),
  EntityFieldSpec(key: "notes", label: "Notes"),
]

let studioFields: [EntityFieldSpec] = [
  EntityFieldSpec(key: "name", label: "Name"),
  EntityFieldSpec(key: "website", label: "Website"),
  EntityFieldSpec(key: "notes", label: "Notes"),
]

let personFields: [EntityFieldSpec] = [
  EntityFieldSpec(key: "name", label: "Name"),
  EntityFieldSpec(key: "notes", label: "Notes"),
]

let licenseFields: [EntityFieldSpec] = [
  EntityFieldSpec(key: "title", label: "Title"),
  EntityFieldSpec(key: "short_title", label: "Short title"),
  EntityFieldSpec(key: "version", label: "Version"),
  EntityFieldSpec(key: "deed", label: "Deed"),
  EntityFieldSpec(key: "legal_code", label: "Legal code"),
  EntityFieldSpec(key: "website", label: "Website"),
  EntityFieldSpec(key: "status", label: "Status"),
  EntityFieldSpec(key: "availability", label: "Availability"),
  EntityFieldSpec(key: "notes", label: "Notes"),
]

func fieldValues(_ p: PublisherViewModel) -> [String: String] {
  ["name": p.name, "address": p.address, "website": p.website, "notes": p.notes]
}

func fieldValues(_ s: StudioViewModel) -> [String: String] {
  ["name": s.name, "website": s.website, "notes": s.notes]
}

func fieldValues(_ p: PersonViewModel) -> [String: String] {
  ["name": p.name, "notes": p.notes]
}

func fieldValues(_ l: LicenseViewModel) -> [String: String] {
  [
    "title": l.title, "short_title": l.shortTitle, "version": l.version, "deed": l.deed,
    "legal_code": l.legalCode, "website": l.website, "status": l.status,
    "availability": l.availability, "notes": l.notes,
  ]
}

/// Browse, detail, and edit pages for publishers, studios, persons, and licenses - the four
/// catalog entity types that, unlike volumes, previously had no pages of their own. One
/// controller for all four types (rather than four near-identical controllers) since their
/// page logic (fetch list, fetch one + its volumes, patch, review) is close to identical - see
/// design.md's "one parameterized controller" decision. Leaf templates stay one file per type
/// (`Resources/Views/<type>/...`), since the four types' attribute sets differ enough that a
/// shared template would need as much per-type conditional logic as separate ones.
struct CatalogEntitiesController: RouteCollection {
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

    routes.get("studios", use: browseStudios)
    routes.get("studios", ":id", use: detailStudio)
    routes.get("studios", ":id", "edit", use: editStudioForm)
    routes.post("studios", ":id", "edit", use: submitStudioEdit)
    routes.post(
      "studios", ":id", "proposed-changes", ":proposalID", "accept", use: acceptStudioProposal)
    routes.post(
      "studios", ":id", "proposed-changes", ":proposalID", "reject", use: rejectStudioProposal)

    routes.get("persons", use: browsePersons)
    routes.get("persons", ":id", use: detailPerson)
    routes.get("persons", ":id", "edit", use: editPersonForm)
    routes.post("persons", ":id", "edit", use: submitPersonEdit)
    routes.post(
      "persons", ":id", "proposed-changes", ":proposalID", "accept", use: acceptPersonProposal)
    routes.post(
      "persons", ":id", "proposed-changes", ":proposalID", "reject", use: rejectPersonProposal)

    routes.get("licenses", use: browseLicenses)
    routes.get("licenses", ":id", use: detailLicense)
    routes.get("licenses", ":id", "edit", use: editLicenseForm)
    routes.post("licenses", ":id", "edit", use: submitLicenseEdit)
    routes.post(
      "licenses", ":id", "proposed-changes", ":proposalID", "accept",
      use: acceptLicenseProposal)
    routes.post(
      "licenses", ":id", "proposed-changes", ":proposalID", "reject",
      use: rejectLicenseProposal)
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

  @Sendable
  func browseStudios(req: Request) async throws -> View {
    let query = try req.query.decode(BrowseQuery.self)
    let studios = try await req.catalogAPI.fetchStudios()
    let filtered = filterByName(studios, query: query.q) { $0.name }

    return try await req.view.render(
      "studios/browse",
      EntityBrowseContext(
        query: query.q ?? "",
        items: filtered.map { LeafStudioCard($0) },
        noResults: filtered.isEmpty,
        user: (await req.currentUser).map(LeafUser.init),
        meta: await PageMeta.make(req)
      ))
  }

  @Sendable
  func detailStudio(req: Request) async throws -> View {
    guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
    guard var studio = try await req.catalogAPI.fetchStudio(id: id) else {
      throw Abort(.notFound)
    }
    studio.volumes = try await req.catalogAPI.fetchStudioVolumes(id: id)
    let sessionUser = await req.currentUser
    let review = await buildReview(
      req: req, path: "/studios", recordID: id, fieldSpecs: studioFields,
      sessionUser: sessionUser)

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

  @Sendable
  func editStudioForm(req: Request) async throws -> View {
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

  @Sendable
  func submitStudioEdit(req: Request) async throws -> Response {
    try await submitEdit(req: req, path: "/studios", fields: studioFields)
  }

  @Sendable
  func acceptStudioProposal(req: Request) async throws -> Response {
    try await acceptProposal(req: req, path: "/studios")
  }

  @Sendable
  func rejectStudioProposal(req: Request) async throws -> Response {
    try await rejectProposal(req: req, path: "/studios")
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

  @Sendable
  func browseLicenses(req: Request) async throws -> View {
    let query = try req.query.decode(BrowseQuery.self)
    let licenses = try await req.catalogAPI.fetchLicenses()
    let filtered = filterByName(licenses, query: query.q) { $0.title }

    return try await req.view.render(
      "licenses/browse",
      EntityBrowseContext(
        query: query.q ?? "",
        items: filtered.map { LeafLicenseCard($0) },
        noResults: filtered.isEmpty,
        user: (await req.currentUser).map(LeafUser.init),
        meta: await PageMeta.make(req)
      ))
  }

  @Sendable
  func detailLicense(req: Request) async throws -> View {
    guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
    guard var license = try await req.catalogAPI.fetchLicense(id: id) else {
      throw Abort(.notFound)
    }
    license.volumes = try await req.catalogAPI.fetchLicenseVolumes(id: id)
    let sessionUser = await req.currentUser
    let review = await buildReview(
      req: req, path: "/licenses", recordID: id, fieldSpecs: licenseFields,
      sessionUser: sessionUser)

    return try await req.view.render(
      "licenses/detail",
      EntityDetailContext(
        license: LeafLicenseDetail(license),
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
  func editLicenseForm(req: Request) async throws -> View {
    guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
    guard let user = await req.currentUser, canEdit(user.roles) else { throw Abort(.forbidden) }
    guard let license = try await req.catalogAPI.fetchLicense(id: id) else {
      throw Abort(.notFound)
    }
    return try await req.view.render(
      "licenses/edit",
      makeEditContext(
        id: id, basePath: "/licenses", fields: licenseFields,
        values: fieldValues(license), user: user, meta: await PageMeta.make(req)))
  }

  @Sendable
  func submitLicenseEdit(req: Request) async throws -> Response {
    try await submitEdit(req: req, path: "/licenses", fields: licenseFields)
  }

  @Sendable
  func acceptLicenseProposal(req: Request) async throws -> Response {
    try await acceptProposal(req: req, path: "/licenses")
  }

  @Sendable
  func rejectLicenseProposal(req: Request) async throws -> Response {
    try await rejectProposal(req: req, path: "/licenses")
  }

  // MARK: - Shared edit/review implementation

  /// Fetches pending proposed changes for (path, recordID) when the session can review them -
  /// mirrors CatalogController.detail's inline proposal-fetch block, factored out since all
  /// four entity types share it. Fails open (nil) on any fetch error, matching that same
  /// fail-open contract, since a review-fetch failure must degrade to "no pending changes
  /// shown" rather than breaking the whole detail page for every editor/admin viewer.
  private func buildReview(
    req: Request, path: String, recordID: String, fieldSpecs: [EntityFieldSpec],
    sessionUser: SessionUser?
  ) async -> LeafEntityProposalReview? {
    let roles = sessionUser?.roles ?? []
    guard canReview(roles), let token = sessionUser?.accessToken else { return nil }
    do {
      let pending = try await req.catalogAPI.listProposedChanges(
        path: path, id: recordID, token: token)
      guard !pending.isEmpty else { return nil }
      let selectedID = req.query[String.self, at: "proposal"]
      let selected = pending.first { $0.id == selectedID } ?? pending[0]
      return LeafEntityProposalReview(
        recordID: recordID, pending: pending, selected: selected, fieldSpecs: fieldSpecs)
    } catch {
      req.logger.warning(
        "failed to fetch proposed changes for \(path)/\(recordID): \(error)")
      return nil
    }
  }

  private func makeEditContext(
    id: String, basePath: String, fields: [EntityFieldSpec], values: [String: String],
    user: SessionUser, meta: PageMeta
  ) -> EntityEditContext {
    EntityEditContext(
      id: id,
      backPath: "\(basePath)/\(id)",
      submitPath: "\(basePath)/\(id)/edit",
      fields: fields.map {
        LeafEntityFieldInput(key: $0.key, label: $0.label, value: values[$0.key] ?? "")
      },
      user: LeafUser(user),
      meta: meta
    )
  }

  private func submitEdit(req: Request, path: String, fields: [EntityFieldSpec]) async throws
    -> Response
  {
    guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
    guard let user = await req.currentUser, canEdit(user.roles) else { throw Abort(.forbidden) }

    let input = try req.content.decode([String: String].self)
    let known = Set(fields.map(\.key))
    let filtered = input.filter { known.contains($0.key) }

    let result = try await req.catalogAPI.patchEntity(
      path: path, id: id, token: user.accessToken, fields: filtered)

    let basePath = "\(req.basePath)\(path)/\(id)"
    switch result {
    case .applied:
      return req.redirect(to: basePath)
    case .proposed:
      return req.redirect(to: "\(basePath)?proposed=1")
    }
  }

  private struct AcceptInput: Content {
    let mode: String
    let fields: [String]?
  }

  private func acceptProposal(req: Request, path: String) async throws -> Response {
    guard let id = req.parameters.get("id"), let proposalID = req.parameters.get("proposalID")
    else {
      throw Abort(.badRequest)
    }
    guard let user = await req.currentUser, canReview(user.roles) else { throw Abort(.forbidden) }
    let input = try req.content.decode(AcceptInput.self)
    let fields: [String]? = input.mode == "all" ? nil : (input.fields ?? [])

    let result = try await req.catalogAPI.acceptProposedChange(
      path: path, id: id, proposalID: proposalID, token: user.accessToken, fields: fields)

    var redirectPath = "\(req.basePath)\(path)/\(id)"
    if let conflicts = result.conflicts, !conflicts.isEmpty {
      redirectPath += "?conflicts=\(conflicts.joined(separator: ","))"
    }
    return req.redirect(to: redirectPath)
  }

  private struct RejectInput: Content {
    let note: String?
  }

  private func rejectProposal(req: Request, path: String) async throws -> Response {
    guard let id = req.parameters.get("id"), let proposalID = req.parameters.get("proposalID")
    else {
      throw Abort(.badRequest)
    }
    guard let user = await req.currentUser, canReview(user.roles) else { throw Abort(.forbidden) }
    let input = try req.content.decode(RejectInput.self)

    _ = try await req.catalogAPI.rejectProposedChange(
      path: path, id: id, proposalID: proposalID, token: user.accessToken, note: input.note)

    return req.redirect(to: "\(req.basePath)\(path)/\(id)")
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

// MARK: - Leaf page contexts

struct EntityBrowseContext<Item: Content>: Content {
  let query: String
  let items: [Item]
  let noResults: Bool
  let user: LeafUser?
  let meta: PageMeta
}

/// One context type covering all four detail pages - only the field matching the page being
/// rendered is non-nil, since each type's template only reads its own field.
struct EntityDetailContext: Content {
  var publisher: LeafPublisherDetail?
  var studio: LeafStudioDetail?
  var person: LeafPersonDetail?
  var license: LeafLicenseDetail?
  let canEdit: Bool
  let justProposed: Bool
  let review: LeafEntityProposalReview?
  let conflicts: [String]
  let user: LeafUser?
  let meta: PageMeta

  init(
    publisher: LeafPublisherDetail? = nil, studio: LeafStudioDetail? = nil,
    person: LeafPersonDetail? = nil, license: LeafLicenseDetail? = nil,
    canEdit: Bool, justProposed: Bool, review: LeafEntityProposalReview?, conflicts: [String],
    user: LeafUser?, meta: PageMeta
  ) {
    self.publisher = publisher
    self.studio = studio
    self.person = person
    self.license = license
    self.canEdit = canEdit
    self.justProposed = justProposed
    self.review = review
    self.conflicts = conflicts
    self.user = user
    self.meta = meta
  }
}

struct EntityEditContext: Content {
  let id: String
  let backPath: String
  let submitPath: String
  let fields: [LeafEntityFieldInput]
  let user: LeafUser?
  let meta: PageMeta
}

struct LeafEntityFieldInput: Content {
  let key: String
  let label: String
  let value: String
}

struct LeafEntityFieldDiff: Content {
  let key: String
  let label: String
  let oldValue: String
  let newValue: String
}

struct LeafEntityProposalOption: Content {
  let id: String
  let submittedBy: String
  let submittedAtLabel: String
  let isSelected: Bool
}

/// The generic counterpart of `LeafProposalReview` (CatalogController.swift), parameterized by
/// a per-type patchable-fields list instead of volume's hardcoded three fields.
struct LeafEntityProposalReview: Content {
  let recordID: String
  let pendingCount: Int
  let hasMultiplePending: Bool
  let options: [LeafEntityProposalOption]
  let selectedID: String
  let submittedBy: String
  let submittedAtLabel: String
  let fields: [LeafEntityFieldDiff]

  init(
    recordID: String, pending: [ProposedChangeSummary], selected: ProposedChangeSummary,
    fieldSpecs: [EntityFieldSpec]
  ) {
    self.recordID = recordID
    self.pendingCount = pending.count
    self.hasMultiplePending = pending.count > 1
    self.options = pending.map { proposal in
      LeafEntityProposalOption(
        id: proposal.id,
        submittedBy: proposal.submittedBy,
        submittedAtLabel: Self.format(proposal.submittedAt),
        isSelected: proposal.id == selected.id
      )
    }
    self.selectedID = selected.id
    self.submittedBy = selected.submittedBy
    self.submittedAtLabel = Self.format(selected.submittedAt)
    self.fields = fieldSpecs.compactMap { field in
      guard let change = selected.diff[field.key] else { return nil }
      return LeafEntityFieldDiff(
        key: field.key, label: field.label,
        oldValue: change.old ?? "", newValue: change.new ?? "")
    }
  }

  private static func format(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }
}

// MARK: - Leaf view models

struct LeafVolumeSummary: Content {
  let id: String
  let title: String

  init(_ summary: VolumeSummary) {
    self.id = summary.id
    self.title = summary.title
  }
}

struct LeafPublisherCard: Content {
  let id: String
  let name: String

  init(_ publisher: PublisherViewModel) {
    self.id = publisher.id
    self.name = publisher.name
  }
}

struct LeafPublisherDetail: Content {
  let id: String
  let name: String
  let address: String
  let hasAddress: Bool
  let website: String
  let hasWebsite: Bool
  let notes: String
  let hasNotes: Bool
  let tags: [String]
  let volumes: [LeafVolumeSummary]
  let hasVolumes: Bool

  init(_ publisher: PublisherViewModel) {
    self.id = publisher.id
    self.name = publisher.name
    self.address = publisher.address
    self.hasAddress = !publisher.address.isEmpty
    self.website = publisher.website
    self.hasWebsite = !publisher.website.isEmpty
    self.notes = publisher.notes
    self.hasNotes = !publisher.notes.isEmpty
    self.tags = publisher.tags
    self.volumes = publisher.volumes.map(LeafVolumeSummary.init)
    self.hasVolumes = !publisher.volumes.isEmpty
  }
}

struct LeafStudioCard: Content {
  let id: String
  let name: String

  init(_ studio: StudioViewModel) {
    self.id = studio.id
    self.name = studio.name
  }
}

struct LeafStudioDetail: Content {
  let id: String
  let name: String
  let website: String
  let hasWebsite: Bool
  let notes: String
  let hasNotes: Bool
  let tags: [String]
  let volumes: [LeafVolumeSummary]
  let hasVolumes: Bool

  init(_ studio: StudioViewModel) {
    self.id = studio.id
    self.name = studio.name
    self.website = studio.website
    self.hasWebsite = !studio.website.isEmpty
    self.notes = studio.notes
    self.hasNotes = !studio.notes.isEmpty
    self.tags = studio.tags
    self.volumes = studio.volumes.map(LeafVolumeSummary.init)
    self.hasVolumes = !studio.volumes.isEmpty
  }
}

struct LeafPersonCard: Content {
  let id: String
  let name: String

  init(_ person: PersonViewModel) {
    self.id = person.id
    self.name = person.name
  }
}

struct LeafPersonDetail: Content {
  let id: String
  let name: String
  let notes: String
  let hasNotes: Bool
  let tags: [String]
  let volumes: [LeafVolumeSummary]
  let hasVolumes: Bool

  init(_ person: PersonViewModel) {
    self.id = person.id
    self.name = person.name
    self.notes = person.notes
    self.hasNotes = !person.notes.isEmpty
    self.tags = person.tags
    self.volumes = person.volumes.map(LeafVolumeSummary.init)
    self.hasVolumes = !person.volumes.isEmpty
  }
}

struct LeafLicenseCard: Content {
  let id: String
  let title: String

  init(_ license: LicenseViewModel) {
    self.id = license.id
    self.title = license.title
  }
}

struct LeafLicenseDetail: Content {
  let id: String
  let title: String
  let shortTitle: String
  let hasShortTitle: Bool
  let version: String
  let hasVersion: Bool
  let deed: String
  let hasDeed: Bool
  let legalCode: String
  let hasLegalCode: Bool
  let website: String
  let hasWebsite: Bool
  let status: String
  let hasStatus: Bool
  let availability: String
  let hasAvailability: Bool
  let notes: String
  let hasNotes: Bool
  let tags: [String]
  let volumes: [LeafVolumeSummary]
  let hasVolumes: Bool

  init(_ license: LicenseViewModel) {
    self.id = license.id
    self.title = license.title
    self.shortTitle = license.shortTitle
    self.hasShortTitle = !license.shortTitle.isEmpty
    self.version = license.version
    self.hasVersion = !license.version.isEmpty
    self.deed = license.deed
    self.hasDeed = !license.deed.isEmpty
    self.legalCode = license.legalCode
    self.hasLegalCode = !license.legalCode.isEmpty
    self.website = license.website
    self.hasWebsite = !license.website.isEmpty
    self.status = license.status
    self.hasStatus = !license.status.isEmpty
    self.availability = license.availability
    self.hasAvailability = !license.availability.isEmpty
    self.notes = license.notes
    self.hasNotes = !license.notes.isEmpty
    self.tags = license.tags
    self.volumes = license.volumes.map(LeafVolumeSummary.init)
    self.hasVolumes = !license.volumes.isEmpty
  }
}
