import CatalogAPIClient
import Crypto
import Foundation
import Vapor

/// Roles that may edit a volume directly (admin/editor) or propose a change for review
/// (submitter) - mirrors auth-api's fixed role model. See platform's
/// volume-edit-authorization spec.
private let editCapableRoles: Set<String> = ["submitter", "editor", "admin"]
/// Roles that may review (list/accept/reject) another user's proposed changes.
private let reviewCapableRoles: Set<String> = ["editor", "admin"]
/// Roles that may upload a volume's cover image - editor/admin only, unlike `editCapableRoles`:
/// there's no submitter-facing proposal flow for a binary file (see design.md's Non-Goals in
/// the catalog-volume-cover-upload OpenSpec change). Currently the same roles as
/// `reviewCapableRoles`, but kept as its own set since the two gate unrelated actions that could
/// diverge later.
private let coverUploadCapableRoles: Set<String> = ["editor", "admin"]

private func canEdit(_ roles: [String]) -> Bool {
  !Set(roles).isDisjoint(with: editCapableRoles)
}

private func canReview(_ roles: [String]) -> Bool {
  !Set(roles).isDisjoint(with: reviewCapableRoles)
}

private func canUploadCover(_ roles: [String]) -> Bool {
  !Set(roles).isDisjoint(with: coverUploadCapableRoles)
}

/// The only `recordType` the durable edit-session mechanism supports today - see
/// docs/frontend-conventions.md's edit-session schema in sweetrpg/platform.
private let recordTypeVolume = "volume"

/// A user's raw Auth0 subject (e.g. `auth0|abc123`, `google-oauth2|123456`) is not a valid
/// assets-web asset id - `|` doesn't survive Werkzeug's `secure_filename`, and assets-web
/// rejects any id that comes back changed. Staged assets are filed under this sanitized form
/// instead (`cover-staged/<sanitized>`) - purely a frontend convention: catalog-api's
/// `editsession`/`proposedchanges` packages treat a staged asset id as an opaque string and
/// never reconstruct it from the sub themselves, so as long as the upload path and the id
/// recorded in the session agree (both computed here), the rest of the system doesn't need to
/// know or care about this sanitization.
private func sanitizedAssetUserID(_ sub: String) -> String {
  sub.replacingOccurrences(of: "|", with: "-")
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
    routes.post("volumes", ":volumeID", "edit", "session", "fields", use: autosaveSessionFields)
    routes.post(
      "volumes", ":volumeID", "edit", "session", "associations", use: autosaveSessionAssociations)
    routes.post("volumes", ":volumeID", "edit", "session", "cover", use: setSessionStagedCover)
    routes.post("volumes", ":volumeID", "edit", "session", "discard", use: discardSession)
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

  /// Loads (or starts) the caller's durable edit session for `volumeID`. Three outcomes:
  /// - no session existed - one is created here, seeded from the volume's live values
  /// - a session already exists for this same volume - resumed as-is (a page reload mid-edit
  ///   must not lose in-progress field values, per task 6.2/6.6)
  /// - a session exists for a *different* volume - returns `nil`, and the caller (`editForm`)
  ///   renders the continue-or-discard prompt instead of the edit page. A session for a
  ///   *different record type* never reaches this branch, since `recordTypeVolume` is fixed.
  private func loadOrStartSession(req: Request, userSub: String, volume: VolumeViewModel)
    async throws -> EditSession?
  {
    if let existing = await req.editSessions.get(userID: userSub, recordType: recordTypeVolume) {
      return existing.recordId == volume.id ? existing : nil
    }

    let now = Date()
    let fresh = EditSession(
      recordId: volume.id,
      fields: [
        "title": .string(volume.title), "description": .string(volume.description),
        "notes": .string(volume.notes),
      ],
      stagedCoverAssetId: nil, sampleAssetIds: nil, createdAt: now, updatedAt: now)
    try await req.editSessions.set(userID: userSub, recordType: recordTypeVolume, session: fresh)
    return fresh
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

    guard let session = try await loadOrStartSession(req: req, userSub: user.sub, volume: volume)
    else {
      let existing = await req.editSessions.get(userID: user.sub, recordType: recordTypeVolume)
      let otherVolume = existing.flatMap { session in
        volumes.first { $0.id == session.recordId }
      }
      return try await req.view.render(
        "edit-session-conflict",
        EditSessionConflictContext(
          volumeID: volumeID,
          volumeTitle: volume.title,
          otherVolumeID: existing?.recordId ?? "",
          otherVolumeTitle: otherVolume?.title ?? "another volume",
          otherStagedCoverPath: existing?.stagedCoverAssetId.map { "asset/cover-staged/\($0)" }
            ?? "",
          user: LeafUser(user),
          meta: await PageMeta.make(req)
        ))
    }

    async let publisherOptions = req.catalogAPI.fetchPublisherOptions()
    async let studioOptions = req.catalogAPI.fetchStudioOptions()

    return try await req.view.render(
      "edit",
      EditContext(
        volume: LeafVolumeEditForm(
          volume: volume, session: session, userSub: sanitizedAssetUserID(user.sub),
          publisherOptions: try await publisherOptions, studioOptions: try await studioOptions),
        canUploadCover: canUploadCover(user.roles),
        submitError: nil,
        user: LeafUser(user),
        meta: await PageMeta.make(req)
      ))
  }

  private struct EditInput: Content {
    let title: String
    let description: String
    let notes: String
  }

  /// Saves the form's current field values into the session (covers any edit not yet synced by
  /// the per-commit autosave calls - e.g. the browser's default blur-before-submit ordering is
  /// not something this app should rely on being awaited in time), then finalizes it. The
  /// session survives a failed finalize (cap reached, or any other error) so the user's
  /// in-progress edit isn't lost - only a successful finalize deletes it (finalize-session does
  /// that server-side on catalog-api's end).
  @Sendable
  func submitEdit(req: Request) async throws -> Response {
    guard let volumeID = req.parameters.get("volumeID") else {
      throw Abort(.badRequest)
    }
    guard let user = await req.currentUser, canEdit(user.roles) else {
      throw Abort(.forbidden)
    }
    let input = try req.content.decode(EditInput.self)

    guard var session = await req.editSessions.get(userID: user.sub, recordType: recordTypeVolume),
      session.recordId == volumeID
    else {
      throw Abort(.badRequest, reason: "No in-flight edit session for this volume")
    }
    session.fields["title"] = .string(input.title)
    session.fields["description"] = .string(input.description)
    session.fields["notes"] = .string(input.notes)
    session.updatedAt = Date()
    try await req.editSessions.set(userID: user.sub, recordType: recordTypeVolume, session: session)

    let basePath = "\(req.basePath)/volumes/\(volumeID)"
    do {
      let result = try await req.catalogAPI.finalizeSession(id: volumeID, token: user.accessToken)
      switch result {
      case .applied:
        return req.redirect(to: basePath)
      case .proposed:
        return req.redirect(to: "\(basePath)?proposed=1")
      }
    } catch let error as CatalogAPIError {
      // Surfaced inline (task 6.5) rather than a generic error page - most commonly the
      // unapproved-submission cap, but any 4xx from finalize-session lands here the same way.
      let volumes = try await req.catalogAPI.fetchVolumes()
      guard let volume = await req.catalogAPI.fetchVolume(id: volumeID, allVolumes: volumes) else {
        throw Abort(.notFound)
      }
      async let publisherOptions = req.catalogAPI.fetchPublisherOptions()
      async let studioOptions = req.catalogAPI.fetchStudioOptions()
      return try await req.view.render(
        "edit",
        EditContext(
          volume: LeafVolumeEditForm(
            volume: volume, session: session, userSub: sanitizedAssetUserID(user.sub),
            publisherOptions: try await publisherOptions, studioOptions: try await studioOptions),
          canUploadCover: canUploadCover(user.roles),
          submitError: error.message ?? "Unable to save your changes. Try again.",
          user: LeafUser(user),
          meta: await PageMeta.make(req)
        )
      ).encodeResponse(status: .badRequest, for: req)
    }
  }

  /// Per-field autosave (task 6.3) - merges whichever of title/description/notes are present
  /// into the session's `fields`, called by the edit page's inline commit handlers. A missing
  /// session (expired, or the user navigated away and back before this fired) 404s rather than
  /// silently recreating one, since re-seeding from live values here could clobber a
  /// browser-side edit already in flight.
  private struct AutosaveFieldsInput: Content {
    let title: String?
    let description: String?
    let notes: String?
  }

  @Sendable
  func autosaveSessionFields(req: Request) async throws -> Response {
    guard let volumeID = req.parameters.get("volumeID") else {
      throw Abort(.badRequest)
    }
    guard let user = await req.currentUser, canEdit(user.roles) else {
      throw Abort(.forbidden)
    }
    guard var session = await req.editSessions.get(userID: user.sub, recordType: recordTypeVolume),
      session.recordId == volumeID
    else {
      throw Abort(.notFound)
    }

    let input = try req.content.decode(AutosaveFieldsInput.self)
    if let title = input.title { session.fields["title"] = .string(title) }
    if let description = input.description { session.fields["description"] = .string(description) }
    if let notes = input.notes { session.fields["notes"] = .string(notes) }
    session.updatedAt = Date()
    try await req.editSessions.set(userID: user.sub, recordType: recordTypeVolume, session: session)

    return Response(status: .noContent)
  }

  /// Publisher/studio linking (task 7.2) - each add/remove click sends the *full* resulting id
  /// list, same full-replace semantics `PATCH /volumes/:id` itself uses for these fields, so
  /// this never needs to diff against what's already in the session.
  private struct AutosaveAssociationsInput: Content {
    let publisherIds: [String]?
    let studioIds: [String]?
  }

  @Sendable
  func autosaveSessionAssociations(req: Request) async throws -> Response {
    guard let volumeID = req.parameters.get("volumeID") else {
      throw Abort(.badRequest)
    }
    guard let user = await req.currentUser, canEdit(user.roles) else {
      throw Abort(.forbidden)
    }
    guard var session = await req.editSessions.get(userID: user.sub, recordType: recordTypeVolume),
      session.recordId == volumeID
    else {
      throw Abort(.notFound)
    }

    let input = try req.content.decode(AutosaveAssociationsInput.self)
    if let publisherIds = input.publisherIds {
      session.fields["publisherIds"] = .stringArray(publisherIds)
    }
    if let studioIds = input.studioIds { session.fields["studioIds"] = .stringArray(studioIds) }
    session.updatedAt = Date()
    try await req.editSessions.set(userID: user.sub, recordType: recordTypeVolume, session: session)

    return Response(status: .noContent)
  }

  /// Records that a cover was staged to `cover-staged/<sub>` on assets-web (the upload itself
  /// happens browser-direct, per task 6.4 - see `edit.leaf`'s script) - this just updates the
  /// session pointer so finalize/discard know a staged file exists.
  private struct SetStagedCoverInput: Content {
    let assetId: String
  }

  @Sendable
  func setSessionStagedCover(req: Request) async throws -> Response {
    guard let volumeID = req.parameters.get("volumeID") else {
      throw Abort(.badRequest)
    }
    guard let user = await req.currentUser, canUploadCover(user.roles) else {
      throw Abort(.forbidden)
    }
    guard var session = await req.editSessions.get(userID: user.sub, recordType: recordTypeVolume),
      session.recordId == volumeID
    else {
      throw Abort(.notFound)
    }

    let input = try req.content.decode(SetStagedCoverInput.self)
    session.stagedCoverAssetId = input.assetId
    session.updatedAt = Date()
    try await req.editSessions.set(userID: user.sub, recordType: recordTypeVolume, session: session)

    return Response(status: .noContent)
  }

  /// Discards the caller's in-flight volume edit session, wherever it points - used both by
  /// "Discard changes" on the edit page itself (redirects back to this volume's detail page)
  /// and by the continue-or-discard prompt's "discard and edit this instead" (redirects back to
  /// *this* volume's edit page, which will then start a fresh session there). Reclaiming a
  /// staged cover is done browser-side before this form submits (see `edit.leaf`/
  /// `edit-session-conflict.leaf`) - assets-web's own auth only accepts browser-originated
  /// requests, not this app's server-to-server calls (see assets-web's AGENTS.md).
  private struct DiscardInput: Content {
    let redirect: String
  }

  @Sendable
  func discardSession(req: Request) async throws -> Response {
    guard req.parameters.get("volumeID") != nil else {
      throw Abort(.badRequest)
    }
    guard let user = await req.currentUser, canEdit(user.roles) else {
      throw Abort(.forbidden)
    }
    let input = try req.content.decode(DiscardInput.self)

    await req.editSessions.delete(userID: user.sub, recordType: recordTypeVolume)

    return req.redirect(to: input.redirect)
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
  /// Set only when `submitEdit` re-renders this page after a failed finalize (e.g. the
  /// unapproved-submission cap) - shown as an inline banner rather than a generic error page,
  /// task 6.5. `nil` on a normal page load.
  let submitError: String?
  /// A *stored* property, not computed from `submitError` - Swift's synthesized `Encodable`
  /// (which `Content` relies on) only encodes stored properties, so a computed `hasX` here
  /// would silently vanish from what Leaf actually sees and always render as false. Set once,
  /// in the initializer.
  let hasSubmitError: Bool
  let user: LeafUser?
  let meta: PageMeta

  init(
    volume: LeafVolumeEditForm, canUploadCover: Bool, submitError: String?, user: LeafUser?,
    meta: PageMeta
  ) {
    self.volume = volume
    self.canUploadCover = canUploadCover
    self.submitError = submitError
    self.hasSubmitError = submitError != nil
    self.user = user
    self.meta = meta
  }
}

/// Shown instead of the edit form when the caller already has an in-flight session for a
/// *different* volume (task 6.2) - a same-type conflict, distinct from having a session for a
/// different record type, which never triggers this at all.
struct EditSessionConflictContext: Content {
  let volumeID: String
  let volumeTitle: String
  let otherVolumeID: String
  let otherVolumeTitle: String
  /// The other session's staged cover path (`asset/cover-staged/<id>`) - lets the "discard and
  /// edit this instead" action reclaim it client-side before discarding, same as `edit.leaf`'s
  /// own discard handler. Empty when the other session has no staged cover.
  let otherStagedCoverPath: String
  /// A *stored* property (see `EditContext.hasSubmitError`'s comment on why this can't be
  /// computed from `otherStagedCoverPath` and still reach Leaf).
  let hasOtherStagedCover: Bool
  let user: LeafUser?
  let meta: PageMeta

  init(
    volumeID: String, volumeTitle: String, otherVolumeID: String, otherVolumeTitle: String,
    otherStagedCoverPath: String, user: LeafUser?, meta: PageMeta
  ) {
    self.volumeID = volumeID
    self.volumeTitle = volumeTitle
    self.otherVolumeID = otherVolumeID
    self.otherVolumeTitle = otherVolumeTitle
    self.otherStagedCoverPath = otherStagedCoverPath
    self.hasOtherStagedCover = !otherStagedCoverPath.isEmpty
    self.user = user
    self.meta = meta
  }
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
  let studioNames: [String]
  let hasStudioNames: Bool
  let licenseNames: [String]
  let hasLicenseNames: Bool
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
    self.studioNames = volume.studioNames
    self.hasStudioNames = !volume.studioNames.isEmpty
    self.licenseNames = volume.licenseNames
    self.hasLicenseNames = !volume.licenseNames.isEmpty
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

/// One entry in a type-to-filter picker's candidate list (publisher/studio today; person in
/// task group 8) - both the full option set (for client-side filtering, task 7.1) and a
/// currently-selected chip use this same shape.
struct LeafNamedOption: Content {
  let id: String
  let name: String
}

struct LeafVolumeEditForm: Content {
  let id: String
  let title: String
  let description: String
  let hasDescription: Bool
  let notes: String
  let hasNotes: Bool
  /// The current session's cover: a staged one if the user has uploaded one this session,
  /// otherwise the volume's existing live cover.
  let coverAssetPath: String
  /// The signed-in user's Auth0 subject - the id staged assets are filed under
  /// (`cover-staged/<sub>`, see docs/frontend-conventions.md's staging convention in
  /// sweetrpg/platform) and this page's JS needs it to build the upload URL.
  let userSub: String
  /// The full publisher candidate list, JSON-encoded for the page's own JS to filter
  /// client-side (task 7.1) - no search endpoint, existing entities only, per design.md.
  let publisherOptionsJSON: String
  let selectedPublishers: [LeafNamedOption]
  let hasSelectedPublishers: Bool
  let studioOptionsJSON: String
  let selectedStudios: [LeafNamedOption]
  let hasSelectedStudios: Bool

  init(
    volume: VolumeViewModel, session: EditSession, userSub: String,
    publisherOptions: [(id: String, name: String)] = [],
    studioOptions: [(id: String, name: String)] = []
  ) {
    self.id = volume.id
    self.title = session.stringField("title") ?? volume.title
    self.description = session.stringField("description") ?? volume.description
    self.hasDescription = !self.description.isEmpty
    self.notes = session.stringField("notes") ?? volume.notes
    self.hasNotes = !self.notes.isEmpty
    self.userSub = userSub
    if let staged = session.stagedCoverAssetId {
      self.coverAssetPath = "asset/cover-staged/\(staged)"
    } else {
      self.coverAssetPath = volume.coverAssetPath
    }

    let publisherByID = Dictionary(uniqueKeysWithValues: publisherOptions)
    let selectedPublisherIds = session.stringArrayField("publisherIds") ?? volume.publisherIds
    self.selectedPublishers = selectedPublisherIds.map {
      LeafNamedOption(id: $0, name: publisherByID[$0] ?? "Unknown publisher")
    }
    self.hasSelectedPublishers = !self.selectedPublishers.isEmpty
    self.publisherOptionsJSON =
      Self.encodeOptions(publisherOptions.map { LeafNamedOption(id: $0.id, name: $0.name) })

    let studioByID = Dictionary(uniqueKeysWithValues: studioOptions)
    let selectedStudioIds = session.stringArrayField("studioIds") ?? volume.studioIds
    self.selectedStudios = selectedStudioIds.map {
      LeafNamedOption(id: $0, name: studioByID[$0] ?? "Unknown studio")
    }
    self.hasSelectedStudios = !self.selectedStudios.isEmpty
    self.studioOptionsJSON =
      Self.encodeOptions(studioOptions.map { LeafNamedOption(id: $0.id, name: $0.name) })
  }

  private static func encodeOptions(_ options: [LeafNamedOption]) -> String {
    (try? JSONEncoder().encode(options)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
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
