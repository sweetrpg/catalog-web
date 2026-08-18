import CatalogAPIClient
import Foundation
import Tracing
import Vapor

/// Status/availability have no backend-defined vocabulary yet (plain free-text strings in
/// catalog-api, no enum, no vocabulary endpoint like format/contribution-type have) - this is a
/// frontend-only closed list, not validated server-side. Confirmed with the user rather than
/// guessed.
private let licenseStatusOptions = ["Draft", "Accepted", "Deprecated", "Retired"]
private let licenseAvailabilityOptions = ["Released", "Withdrawn"]

let licenseFields: [EntityFieldSpec] = [
  EntityFieldSpec(key: "title", label: "Title"),
  EntityFieldSpec(key: "short_title", label: "Short title"),
  EntityFieldSpec(key: "version", label: "Version"),
  EntityFieldSpec(key: "website", label: "Website"),
  EntityFieldSpec(key: "status", label: "Status", kind: .select(options: licenseStatusOptions)),
  EntityFieldSpec(
    key: "availability", label: "Availability",
    kind: .select(options: licenseAvailabilityOptions)),
  EntityFieldSpec(key: "notes", label: "Notes"),
  // Long-form text (deed can be markdown, legal_code is a full license text) - textarea, and
  // kept last per the page's field order.
  EntityFieldSpec(key: "deed", label: "Deed", kind: .textarea),
  EntityFieldSpec(key: "legal_code", label: "Legal code", kind: .textarea),
]

func fieldValues(_ l: LicenseViewModel) -> [String: String] {
  [
    "title": l.title, "short_title": l.shortTitle, "version": l.version, "deed": l.deed,
    "legal_code": l.legalCode, "website": l.website, "status": l.status,
    "availability": l.availability, "notes": l.notes,
  ]
}

func fieldValues(_ l: LicenseVersionAttributes) -> [String: String] {
  [
    "title": l.title, "short_title": l.shortTitle, "version": l.licenseVersion, "deed": l.deed,
    "legal_code": l.legalCode, "status": l.status, "availability": l.availability,
    "notes": l.notes,
  ]
}

/// Browse, detail, and edit pages for publishers, studios, persons, and licenses - the four
/// catalog entity types that, unlike volumes, previously had no pages of their own. One
/// controller for all four types (rather than four near-identical controllers) since their
/// page logic (fetch list, fetch one + its volumes, patch, review) is close to identical - see
/// design.md's "one parameterized controller" decision. Leaf templates stay one file per type
/// (`Resources/Views/<type>/...`), since the four types' attribute sets differ enough that a
/// shared template would need as much per-type conditional logic as separate ones.
struct LicensesController: RouteCollection {
  func boot(routes: RoutesBuilder) throws {
    routes.get("licenses", use: browseLicenses)
    routes.get("licenses", ":id", use: detailLicense)
    routes.get("licenses", ":id", "edit", use: editLicenseForm)
    routes.post("licenses", ":id", "edit", use: submitLicenseEdit)
    routes.post(
      "licenses", ":id", "versions", ":version", "accept",
      use: acceptLicenseVersion)
    routes.post(
      "licenses", ":id", "versions", ":version", "reject",
      use: rejectLicenseVersion)
  }

  private struct BrowseQuery: Content {
    let q: String?
    let order: String?
  }

  @Sendable
  func browseLicenses(req: Request) async throws -> View {
    try await withSpan("licenses-browse") { _ in
      let query = try req.query.decode(BrowseQuery.self)
      let order = resolveBrowseSortOrder(query.order)
      let licenses = try await req.catalogAPI.fetchLicenses()
      let filtered = filterByName(licenses, query: query.q) { $0.title }
      let sorted = sortByName(filtered, order: order) { $0.title }

      return try await req.view.render(
        "licenses/browse",
        EntityBrowseContext(
          query: query.q ?? "",
          items: sorted.map { LeafLicenseCard($0) },
          noResults: filtered.isEmpty,
          orderIsAsc: order == .asc,
          orderIsDesc: order == .desc,
          user: (await req.currentUser).map(LeafUser.init),
          meta: await PageMeta.make(req)
        ))
    }
  }

  @Sendable
  func detailLicense(req: Request) async throws -> View {
    try await withSpan("licenses-detail") { _ in
      guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
      guard var license = try await req.catalogAPI.fetchLicense(id: id) else {
        throw Abort(.notFound)
      }
      license.volumes = try await req.catalogAPI.fetchLicenseVolumes(id: id)
      let sessionUser = await req.currentUser
      let review: LeafEntityVersionReview? = await buildReview(
        req: req, path: "/licenses", recordID: id, fieldSpecs: licenseFields,
        currentValues: fieldValues(license), sessionUser: sessionUser,
        versionFieldValues: { (v: LicenseVersionAttributes) in fieldValues(v) })

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
  }

  @Sendable
  func editLicenseForm(req: Request) async throws -> View {
    try await withSpan("licenses-edit") { _ in
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
  }

  @Sendable
  func submitLicenseEdit(req: Request) async throws -> Response {
    try await submitEdit(req: req, path: "/licenses", fields: licenseFields)
  }

  @Sendable
  func acceptLicenseVersion(req: Request) async throws -> Response {
    try await acceptVersionReview(req: req, path: "/licenses")
  }

  @Sendable
  func rejectLicenseVersion(req: Request) async throws -> Response {
    try await rejectVersionReview(req: req, path: "/licenses")
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
