import CatalogAPIClient
import Crypto
import Foundation
import Vapor

/// Roles that may edit a volume (or, since `catalog-entity-pages`, a publisher/studio/person/
/// license) directly (admin/editor) or propose a change for review (submitter) - mirrors
/// auth-api's fixed role model. See platform's volume-edit-authorization spec. Not file-private
/// - `CatalogEntitiesController` reuses `canEdit`/`canReview` for the same role gating.
let editCapableRoles: Set<String> = ["submitter", "editor", "admin"]
/// Roles that may review (list/accept/reject) another user's proposed changes.
let reviewCapableRoles: Set<String> = ["editor", "admin"]
/// Roles that may upload a volume's cover image - editor/admin only, unlike `editCapableRoles`:
/// there's no submitter-facing proposal flow for a binary file (see design.md's Non-Goals in
/// the catalog-volume-cover-upload OpenSpec change). Currently the same roles as
/// `reviewCapableRoles`, but kept as its own set since the two gate unrelated actions that could
/// diverge later.
private let coverUploadCapableRoles: Set<String> = ["editor", "admin"]

func canEdit(_ roles: [String]) -> Bool {
  !Set(roles).isDisjoint(with: editCapableRoles)
}

func canReview(_ roles: [String]) -> Bool {
  !Set(roles).isDisjoint(with: reviewCapableRoles)
}

private func canUploadCover(_ roles: [String]) -> Bool {
  !Set(roles).isDisjoint(with: coverUploadCapableRoles)
}

/// Home, Browse, and Volume Detail - the three catalog-browsing pages, all backed by
/// catalog-api. Grouped in one controller since they share the same volume-fetching path,
/// unlike ShelvesController, which has its own concern.
struct CatalogController: RouteCollection {
  func boot(routes: RoutesBuilder) throws {
    routes.get(use: home)
    routes.get("browse", use: browse)
    routes.get("volumes", ":volumeID", use: detail)
    routes.get("volumes", ":volumeID", "edit", use: editForm)
    routes.post("volumes", ":volumeID", "edit", use: submitEdit)
    routes.post(
      "volumes", ":volumeID", "proposed-changes", ":proposalID", "accept", use: acceptProposal)
    routes.post(
      "volumes", ":volumeID", "proposed-changes", ":proposalID", "reject", use: rejectProposal)
  }

  @Sendable
  func home(req: Request) async throws -> View {
    let volumes = try await req.catalogAPI.fetchVolumes()
    let trending = Array(volumes.prefix(8))
    let tagCloud = Array(Set(volumes.flatMap(\.tags))).sorted().prefix(14)

    return try await req.view.render(
      "home",
      HomeContext(
        volumeCount: volumes.count,
        trending: trending.map(LeafVolumeCard.init),
        tagCloud: tagCloud.map { LeafTag(name: $0) },
        user: (await req.currentUser).map(LeafUser.init),
        meta: await PageMeta.make(req)
      ))
  }

  @Sendable
  func browse(req: Request) async throws -> View {
    struct Query: Content {
      let q: String?
      let tag: String?
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

    return try await req.view.render(
      "browse",
      BrowseContext(
        query: query.q ?? "",
        noActiveTag: query.tag == nil || query.tag!.isEmpty,
        tagCloud: tagCloud.map { LeafTag(name: $0, isActive: $0 == query.tag) },
        volumes: filtered.map(LeafVolumeCard.init),
        noResults: filtered.isEmpty,
        user: (await req.currentUser).map(LeafUser.init),
        meta: await PageMeta.make(req)
      ))
  }

  @Sendable
  func detail(req: Request) async throws -> View {
    guard let volumeID = req.parameters.get("volumeID") else {
      throw Abort(.badRequest)
    }
    let volumes = try await req.catalogAPI.fetchVolumes()
    guard var volume = await req.catalogAPI.fetchVolume(id: volumeID, allVolumes: volumes)
    else {
      throw Abort(.notFound)
    }
    volume.credits = try await req.catalogAPI.fetchCredits(volumeID: volumeID)
    volume.reviews = try await req.catalogAPI.fetchReviews(volumeID: volumeID)

    let sessionUser = await req.currentUser
    let roles = sessionUser?.roles ?? []

    var proposalReview: LeafProposalReview?
    if canReview(roles), let token = sessionUser?.accessToken {
      // Fails open rather than propagating: catalog-api's proposed-changes endpoints are a
      // separate deployment from this app's own release, so a version skew or outage there
      // (e.g. the endpoint not yet shipped) must degrade to "no pending changes shown", not
      // 500 the entire detail page for every editor/admin viewer - matches AdminClient's and
      // this app's session-read fail-open contract elsewhere.
      do {
        let pending = try await req.catalogAPI.listProposedChanges(
          volumeID: volumeID, token: token)
        if !pending.isEmpty {
          let selectedID = req.query[String.self, at: "proposal"]
          let selected = pending.first { $0.id == selectedID } ?? pending[0]
          proposalReview = LeafProposalReview(
            volumeID: volumeID, pending: pending, selected: selected)
        }
      } catch {
        req.logger.warning(
          "failed to fetch proposed changes for volume \(volumeID): \(error)")
      }
    }

    let conflicts = (req.query[String.self, at: "conflicts"] ?? "")
      .split(separator: ",").map(String.init)

    return try await req.view.render(
      "detail",
      DetailContext(
        volume: LeafVolumeDetail(volume),
        canEdit: canEdit(roles),
        justProposed: req.query[String.self, at: "proposed"] == "1",
        review: proposalReview,
        conflicts: conflicts,
        hasConflicts: !conflicts.isEmpty,
        user: sessionUser.map(LeafUser.init),
        meta: await PageMeta.make(req)
      ))
  }

  @Sendable
  func editForm(req: Request) async throws -> View {
    guard let volumeID = req.parameters.get("volumeID") else {
      throw Abort(.badRequest)
    }
    guard let user = await req.currentUser, canEdit(user.roles) else {
      throw Abort(.forbidden)
    }
    let volumes = try await req.catalogAPI.fetchVolumes()
    guard let volume = await req.catalogAPI.fetchVolume(id: volumeID, allVolumes: volumes) else {
      throw Abort(.notFound)
    }

    return try await req.view.render(
      "edit",
      EditContext(
        volume: LeafVolumeEditForm(volume),
        canUploadCover: canUploadCover(user.roles),
        user: LeafUser(user),
        meta: await PageMeta.make(req)
      ))
  }

  private struct EditInput: Content {
    let title: String
    let description: String
    let notes: String
  }

  @Sendable
  func submitEdit(req: Request) async throws -> Response {
    guard let volumeID = req.parameters.get("volumeID") else {
      throw Abort(.badRequest)
    }
    guard let user = await req.currentUser, canEdit(user.roles) else {
      throw Abort(.forbidden)
    }
    let input = try req.content.decode(EditInput.self)

    let result = try await req.catalogAPI.patchVolume(
      id: volumeID, token: user.accessToken,
      title: input.title, description: input.description, notes: input.notes)

    let basePath = "\(req.basePath)/volumes/\(volumeID)"
    switch result {
    case .applied:
      return req.redirect(to: basePath)
    case .proposed:
      return req.redirect(to: "\(basePath)?proposed=1")
    }
  }

  /// `mode` distinguishes "accept every changed field" (the Accept All button, no `fields` sent)
  /// from "accept only the checked fields" (the Accept Selected button) - without it, a subset
  /// submission where the reviewer unchecked every box would arrive as an absent `fields` key,
  /// indistinguishable from "accept all" and silently applying fields the reviewer meant to
  /// reject. With `mode`, that case instead sends an explicit empty array, which catalog-api
  /// treats as "reject everything" - the safe direction for an ambiguous submission.
  private struct AcceptInput: Content {
    let mode: String
    let fields: [String]?
  }

  @Sendable
  func acceptProposal(req: Request) async throws -> Response {
    guard let volumeID = req.parameters.get("volumeID"),
      let proposalID = req.parameters.get("proposalID")
    else {
      throw Abort(.badRequest)
    }
    guard let user = await req.currentUser, canReview(user.roles) else {
      throw Abort(.forbidden)
    }
    let input = try req.content.decode(AcceptInput.self)
    let fields: [String]? = input.mode == "all" ? nil : (input.fields ?? [])

    let result = try await req.catalogAPI.acceptProposedChange(
      volumeID: volumeID, proposalID: proposalID, token: user.accessToken, fields: fields)

    var redirectPath = "\(req.basePath)/volumes/\(volumeID)"
    if let conflicts = result.conflicts, !conflicts.isEmpty {
      redirectPath += "?conflicts=\(conflicts.joined(separator: ","))"
    }
    return req.redirect(to: redirectPath)
  }

  private struct RejectInput: Content {
    let note: String?
  }

  @Sendable
  func rejectProposal(req: Request) async throws -> Response {
    guard let volumeID = req.parameters.get("volumeID"),
      let proposalID = req.parameters.get("proposalID")
    else {
      throw Abort(.badRequest)
    }
    guard let user = await req.currentUser, canReview(user.roles) else {
      throw Abort(.forbidden)
    }
    let input = try req.content.decode(RejectInput.self)

    _ = try await req.catalogAPI.rejectProposedChange(
      volumeID: volumeID, proposalID: proposalID, token: user.accessToken, note: input.note)

    return req.redirect(to: "\(req.basePath)/volumes/\(volumeID)")
  }
}

// MARK: - Leaf page contexts

/// Concrete, per-page Encodable structs - not `[String: Encodable]` dictionaries. Swift's
/// `Dictionary` only conditionally conforms to `Encodable` when its `Value` is *concretely*
/// `Encodable`; `any Encodable` as the value type doesn't satisfy that, so a dictionary typed
/// `[String: Encodable]` does not itself conform to `Encodable` and can't be passed to
/// `req.view.render`, which requires a real `Encodable` context type.

struct HomeContext: Content {
  let volumeCount: Int
  let trending: [LeafVolumeCard]
  let tagCloud: [LeafTag]
  let user: LeafUser?
  let meta: PageMeta
}

struct BrowseContext: Content {
  let query: String
  let noActiveTag: Bool
  let tagCloud: [LeafTag]
  let volumes: [LeafVolumeCard]
  let noResults: Bool
  let user: LeafUser?
  let meta: PageMeta
}

struct DetailContext: Content {
  let volume: LeafVolumeDetail
  /// `true` when the signed-in session's roles include submitter/editor/admin - gates the
  /// "Edit" action. `false` (including for an anonymous visitor) hides it entirely.
  let canEdit: Bool
  /// `true` right after a submitter's edit was stored as a proposed change rather than applied
  /// (the `?proposed=1` redirect query param) - shows a "pending review" banner instead of the
  /// change appearing to silently have no effect.
  let justProposed: Bool
  /// Present only for an editor/admin viewer when at least one proposed change is pending -
  /// nil hides the entire review section, including for a submitter who has no review rights.
  let review: LeafProposalReview?
  /// Field names catalog-api flagged as conflicting on the most recent accept action (via the
  /// `?conflicts=` redirect query param) - the live record changed since the proposal was
  /// submitted, so that field wasn't applied. Empty outside of that redirect.
  let conflicts: [String]
  /// `true` only when `conflicts` is non-empty - Leaf's `#if` treats an empty array as truthy,
  /// so the template branches on this instead of `conflicts` directly (same reason
  /// `LeafVolumeDetail` exposes `hasSystemNames` etc. alongside each array).
  let hasConflicts: Bool
  let user: LeafUser?
  let meta: PageMeta
}

struct EditContext: Content {
  let volume: LeafVolumeEditForm
  /// `true` when the signed-in session's roles include editor/admin - gates the cover-upload
  /// control. Every viewer of this page already passed `canEdit` (enforced in `editForm`), but
  /// cover upload is editor/admin-only, same as on the detail page before it moved here.
  let canUploadCover: Bool
  let user: LeafUser?
  let meta: PageMeta
}

// MARK: - Leaf view models

/// Flat, Leaf-friendly wrappers around the domain models above. Kept separate from
/// `VolumeViewModel` etc. so the API-facing models don't accumulate template-only convenience
/// properties (`ratingStars`, `hasX` booleans) that have nothing to do with fetching data.

struct LeafTag: Content {
  let name: String
  var isActive: Bool = false
}

struct LeafUser: Content {
  let name: String
  /// Shown as a smaller, muted subtitle line under `name` in the avatar menu. `nil` when the
  /// session has no email (same source as `avatarGravatarURL` below).
  let email: String?
  /// First character of `name`, uppercased - the avatar trigger's label.
  let avatarInitial: String
  /// Gravatar image URL derived from the session's email (`d=404` so a visitor with no
  /// Gravatar gets a real 404 rather than Gravatar's generic mystery-person image) - the
  /// shared avatar-menu markup's `onerror` falls back to `avatarInitial` on load failure.
  /// `nil` when the session has no email.
  let avatarGravatarURL: String?
  /// `true` when the session's `roles` (verified by `users-api`) includes `admin` - gates the
  /// avatar menu's "Admin" item, mirroring `admin-web`'s own `AuthRequiredMiddleware` role
  /// check.
  let isAdmin: Bool

  init(_ user: SessionUser) {
    self.name = user.name
    self.email = user.email
    self.avatarInitial = user.name.first.map { String($0).uppercased() } ?? ""
    self.avatarGravatarURL = user.email.map { email in
      let canonical = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      let hash = Insecure.MD5.hash(data: Data(canonical.utf8))
        .map { String(format: "%02x", $0) }
        .joined()
      return "https://www.gravatar.com/avatar/\(hash)?s=64&d=404"
    }
    self.isAdmin = user.roles.contains("admin")
  }
}

struct LeafVolumeCard: Content {
  let id: String
  let title: String
  let tagChips: [String]
  let coverAssetPath: String

  init(_ volume: VolumeViewModel) {
    self.id = volume.id
    self.title = volume.title
    self.tagChips = volume.tagChips
    self.coverAssetPath = volume.coverAssetPath
  }
}

struct LeafEntityRef: Content {
  let id: String
  let name: String

  init(_ ref: EntityRef) {
    self.id = ref.id
    self.name = ref.name
  }
}

struct LeafVolumeDetail: Content {
  let id: String
  let title: String
  let description: String
  let hasDescription: Bool
  let notes: String
  let hasNotes: Bool
  let tags: [String]
  let systemNames: [String]
  let hasSystemNames: Bool
  let publisherNames: [String]
  let hasPublisherNames: Bool
  let publisherRefs: [LeafEntityRef]
  let studioNames: [String]
  let hasStudioNames: Bool
  let studioRefs: [LeafEntityRef]
  let licenseNames: [String]
  let hasLicenseNames: Bool
  let licenseRefs: [LeafEntityRef]
  let credits: [LeafCredit]
  let hasCredits: Bool
  let reviews: [LeafReview]
  let hasReviews: Bool
  let coverAssetPath: String

  init(_ volume: VolumeViewModel) {
    self.id = volume.id
    self.title = volume.title
    self.description = volume.description
    self.hasDescription = !volume.description.isEmpty
    self.notes = volume.notes
    self.hasNotes = !volume.notes.isEmpty
    self.tags = volume.tags
    self.systemNames = volume.systemNames
    self.hasSystemNames = !volume.systemNames.isEmpty
    self.publisherNames = volume.publisherNames
    self.hasPublisherNames = !volume.publisherNames.isEmpty
    self.publisherRefs = volume.publisherRefs.map(LeafEntityRef.init)
    self.studioNames = volume.studioNames
    self.hasStudioNames = !volume.studioNames.isEmpty
    self.studioRefs = volume.studioRefs.map(LeafEntityRef.init)
    self.licenseNames = volume.licenseNames
    self.hasLicenseNames = !volume.licenseNames.isEmpty
    self.licenseRefs = volume.licenseRefs.map(LeafEntityRef.init)
    self.credits = volume.credits.map(LeafCredit.init)
    self.hasCredits = !volume.credits.isEmpty
    self.reviews = volume.reviews.map(LeafReview.init)
    self.hasReviews = !volume.reviews.isEmpty
    self.coverAssetPath = volume.coverAssetPath
  }
}

struct LeafCredit: Content {
  let role: String
  let person: String

  init(_ credit: (role: String, person: String)) {
    self.role = credit.role
    self.person = credit.person
  }
}

struct LeafReview: Content {
  let author: String
  let starsLabel: String
  let text: String

  init(_ review: (author: String, rating: Int, text: String)) {
    self.author = review.author
    self.starsLabel =
      String(repeating: "\u{2605}", count: max(0, min(5, review.rating)))
      + String(repeating: "\u{2606}", count: max(0, 5 - review.rating))
    self.text = review.text
  }
}

struct LeafVolumeEditForm: Content {
  let id: String
  let title: String
  let description: String
  let notes: String
  let coverAssetPath: String

  init(_ volume: VolumeViewModel) {
    self.id = volume.id
    self.title = volume.title
    self.description = volume.description
    self.notes = volume.notes
    self.coverAssetPath = volume.coverAssetPath
  }
}

/// The volume detail page's fixed, ordered list of fields a `PATCH`/proposal can touch -
/// `ProposedChangeSummary.diff` is a `[String: FieldChange]` dictionary with no defined
/// iteration order, so the diff table and review UI both walk this list instead of the raw
/// dictionary keys, keeping row order stable and matching the edit form's field order.
private let patchableFields: [(key: String, label: String)] = [
  ("title", "Title"),
  ("description", "Description"),
  ("notes", "Notes"),
]

struct LeafFieldDiff: Content {
  let key: String
  let label: String
  let oldValue: String
  let newValue: String
}

struct LeafProposalOption: Content {
  let id: String
  let submittedBy: String
  let submittedAtLabel: String
  let isSelected: Bool
}

struct LeafProposalReview: Content {
  let volumeID: String
  let pendingCount: Int
  let hasMultiplePending: Bool
  let options: [LeafProposalOption]
  let selectedID: String
  let submittedBy: String
  let submittedAtLabel: String
  let fields: [LeafFieldDiff]

  init(volumeID: String, pending: [ProposedChangeSummary], selected: ProposedChangeSummary) {
    self.volumeID = volumeID
    self.pendingCount = pending.count
    self.hasMultiplePending = pending.count > 1
    self.options = pending.map { proposal in
      LeafProposalOption(
        id: proposal.id,
        submittedBy: proposal.submittedBy,
        submittedAtLabel: Self.format(proposal.submittedAt),
        isSelected: proposal.id == selected.id
      )
    }
    self.selectedID = selected.id
    self.submittedBy = selected.submittedBy
    self.submittedAtLabel = Self.format(selected.submittedAt)
    self.fields = patchableFields.compactMap { field in
      guard let change = selected.diff[field.key] else { return nil }
      return LeafFieldDiff(
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
