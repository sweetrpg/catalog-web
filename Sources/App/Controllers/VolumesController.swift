import CatalogAPIClient
import Foundation
import Vapor

/// Browse, detail, and edit pages for publishers, studios, persons, and licenses - the four
/// catalog entity types that, unlike volumes, previously had no pages of their own. One
/// controller for all four types (rather than four near-identical controllers) since their
/// page logic (fetch list, fetch one + its volumes, patch, review) is close to identical - see
/// design.md's "one parameterized controller" decision. Leaf templates stay one file per type
/// (`Resources/Views/<type>/...`), since the four types' attribute sets differ enough that a
/// shared template would need as much per-type conditional logic as separate ones.
struct VolumesController: RouteCollection {
  func boot(routes: RoutesBuilder) throws {
    routes.get("volumes", ":volumeID", use: detail)
    routes.get("volumes", ":volumeID", "edit", use: editForm)
    routes.post("volumes", ":volumeID", "edit", use: submitEdit)
    routes.post("volumes", ":volumeID", "edit", "session", "fields", use: autosaveSessionFields)
    routes.post(
      "volumes", ":volumeID", "edit", "session", "associations", use: autosaveSessionAssociations)
    routes.post("volumes", ":volumeID", "edit", "session", "cover", use: setSessionStagedCover)
    routes.post("volumes", ":volumeID", "edit", "session", "credits", use: autosaveSessionCredits)
    routes.post(
      "volumes", ":volumeID", "edit", "session", "properties", use: autosaveSessionProperties)
    routes.post("volumes", ":volumeID", "edit", "session", "format", use: autosaveSessionFormat)
    routes.post("volumes", ":volumeID", "edit", "session", "samples", use: autosaveSessionSamples)
    routes.post("volumes", ":volumeID", "edit", "session", "discard", use: discardSession)
    routes.post("volumes", ":volumeID", "edit", "vocabulary", ":type", use: addVocabularyValue)
    routes.post(
      "volumes", ":volumeID", "proposed-changes", ":proposalID", "accept", use: acceptProposal)
    routes.post(
      "volumes", ":volumeID", "proposed-changes", ":proposalID", "reject", use: rejectProposal)
    routes.get("volumes", ":volumeID", "versions", use: versionHistory)
    routes.get("volumes", ":volumeID", "versions", ":version", use: versionDetail)
    routes.post(
      "volumes", ":volumeID", "versions", ":version", "restore", use: restoreVersion)
  }

  private struct BrowseQuery: Content {
    let q: String?
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

  /// Lists a volume's version history, newest first - anyone who can view the volume itself can
  /// view its history (no role gate on the list/detail views; only restoring a past version is
  /// role-gated, per `canRollback`).
  @Sendable
  func versionHistory(req: Request) async throws -> View {
    guard let volumeID = req.parameters.get("volumeID") else {
      throw Abort(.badRequest)
    }
    let volumes = try await req.catalogAPI.fetchVolumes()
    guard let volume = await req.catalogAPI.fetchVolume(id: volumeID, allVolumes: volumes) else {
      throw Abort(.notFound)
    }
    let sessionUser = await req.currentUser
    let roles = sessionUser?.roles ?? []
    // Fails open the same way the review section does (detail(_:)) - a version-skewed or
    // unavailable catalog-api deployment shows an empty history rather than 500ing the page.
    var versions: [VolumeVersionAttributes] = []
    if let token = sessionUser?.accessToken {
      do {
        versions = try await req.catalogAPI.fetchVolumeVersions(volumeID: volumeID, token: token)
      } catch {
        req.logger.warning("failed to fetch versions for volume \(volumeID): \(error)")
      }
    }

    return try await req.view.render(
      "version-history",
      VersionHistoryContext(
        volumeID: volumeID,
        volumeTitle: volume.title,
        versions: versions.map(LeafVersionSummary.init),
        canRollback: canRollback(roles),
        user: sessionUser.map(LeafUser.init),
        meta: await PageMeta.make(req)
      ))
  }

  /// Shows one version's full field snapshot.
  @Sendable
  func versionDetail(req: Request) async throws -> View {
    guard let volumeID = req.parameters.get("volumeID"),
      let versionParam = req.parameters.get("version"), let version = Int(versionParam)
    else {
      throw Abort(.badRequest)
    }
    let sessionUser = await req.currentUser
    guard let token = sessionUser?.accessToken else {
      throw Abort(.notFound)
    }
    let versionAttributes: VolumeVersionAttributes
    do {
      versionAttributes = try await req.catalogAPI.fetchVolumeVersion(
        volumeID: volumeID, version: version, token: token)
    } catch let error as CatalogAPIError where error.statusCode == 404 {
      throw Abort(.notFound)
    }

    return try await req.view.render(
      "version-detail",
      VersionDetailContext(
        volumeID: volumeID,
        version: LeafVersionDetail(versionAttributes),
        canRollback: canRollback(sessionUser?.roles ?? []),
        user: sessionUser.map(LeafUser.init),
        meta: await PageMeta.make(req)
      ))
  }

  /// Restores an arbitrary past version as current - admin only, enforced both here and by
  /// catalog-api itself.
  @Sendable
  func restoreVersion(req: Request) async throws -> Response {
    guard let volumeID = req.parameters.get("volumeID"),
      let versionParam = req.parameters.get("version"), let version = Int(versionParam)
    else {
      throw Abort(.badRequest)
    }
    guard let user = await req.currentUser, canRollback(user.roles) else {
      throw Abort(.forbidden)
    }

    _ = try await req.catalogAPI.setCurrentVolumeVersion(
      volumeID: volumeID, version: version, token: user.accessToken)

    return req.redirect(to: "\(req.basePath)/volumes/\(volumeID)")
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
    req.logger.info("loadOrStartSession: user \(userSub); volume \(volume.id)")

    if let existing = await req.editSessions.get(userID: userSub, recordType: recordTypeVolume) {
      return existing.recordId == volume.id ? existing : nil
    }

    req.logger.info("loadOrStartSession: starting new session for user \(userSub); volume \(volume.id)")

    let now = Date()
    let fresh = EditSession(
      recordId: volume.id,
      fields: [
        "title": .string(volume.title), "description": .string(volume.description),
        "notes": .string(volume.notes),
      ],
      stagedCoverAssetId: nil, sampleAssetIds: nil, createdAt: now, updatedAt: now)
    try await req.editSessions.set(userID: userSub, recordType: recordTypeVolume, session: fresh)

    req.logger.info("loadOrStartSession: new session started for user \(userSub); volume \(volume.id)")

    return fresh
  }

  @Sendable
  func editForm(req: Request) async throws -> View {
    req.logger.info("editForm: volumeID=\(String(describing: req.parameters.get("volumeID")))")

    guard let volumeID = req.parameters.get("volumeID") else {
      req.logger.error("editForm: volumeID is missing")
      throw Abort(.badRequest)
    }
    guard let user = await req.currentUser, canEdit(user.roles) else {
      req.logger.error("editForm: user is not authorized")
      throw Abort(.forbidden)
    }
    let volumes = try await req.catalogAPI.fetchVolumes() // TODO: fix this travesty
    guard let volume = await req.catalogAPI.fetchVolume(id: volumeID, allVolumes: volumes) else {
      req.logger.error("editForm: volume \(volumeID) not found")
      throw Abort(.notFound)
    }

    guard let session = try await loadOrStartSession(req: req, userSub: user.sub, volume: volume)
    else {
      let existing = await req.editSessions.get(userID: user.sub, recordType: recordTypeVolume)
      let otherVolume = existing.flatMap { session in
        volumes.first { $0.id == session.recordId }
      }

      req.logger.info("editForm: session conflict for user \(user.sub); volume \(volumeID) vs \(existing?.recordId ?? "another volume")")

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
    async let personOptions = req.catalogAPI.fetchPersonOptions()
    async let contributionTypeOptions = req.catalogAPI.fetchVocabulary(
      type: "contribution-type", token: user.accessToken)
    async let propertyNameOptions = req.catalogAPI.fetchVocabulary(
      type: "property-name", token: user.accessToken)
    async let existingCredits = req.catalogAPI.fetchCredits(volumeID: volumeID)
    // Only fetched for editor/admin - a submitter's token gets a 403 from
    // GET /vocabularies/format itself (see `volume-format-selector`'s spec), so this must not
    // even attempt the call for a submitter session.
    let canSetFormat = canCreateVocabularyValue(user.roles)
    let formatOptions =
      canSetFormat
      ? try await req.catalogAPI.fetchVocabulary(type: "format", token: user.accessToken) : []

    var volumeWithCredits = volume
    volumeWithCredits.credits = try await existingCredits

    req.logger.info("editForm: volume \(volumeID) loaded for user \(user.sub)")

    return try await req.view.render(
      "edit",
      EditContext(
        volume: LeafVolumeEditForm(
          volume: volumeWithCredits, session: session, userSub: sanitizedAssetUserID(user.sub),
          publisherOptions: try await publisherOptions, studioOptions: try await studioOptions,
          personOptions: try await personOptions,
          contributionTypeOptions: try await contributionTypeOptions,
          canAddContributionType: canCreateVocabularyValue(user.roles),
          propertyNameOptions: try await propertyNameOptions,
          canAddPropertyName: canCreateVocabularyValue(user.roles),
          formatOptions: formatOptions, canSetFormat: canSetFormat),
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
      async let personOptions = req.catalogAPI.fetchPersonOptions()
      async let contributionTypeOptions = req.catalogAPI.fetchVocabulary(
        type: "contribution-type", token: user.accessToken)
      async let propertyNameOptions = req.catalogAPI.fetchVocabulary(
        type: "property-name", token: user.accessToken)
      async let existingCredits = req.catalogAPI.fetchCredits(volumeID: volumeID)
      let canSetFormat = canCreateVocabularyValue(user.roles)
      let formatOptions =
        canSetFormat
        ? try await req.catalogAPI.fetchVocabulary(type: "format", token: user.accessToken) : []

      var volumeWithCredits = volume
      volumeWithCredits.credits = try await existingCredits

      return try await req.view.render(
        "edit",
        EditContext(
          volume: LeafVolumeEditForm(
            volume: volumeWithCredits, session: session, userSub: sanitizedAssetUserID(user.sub),
            publisherOptions: try await publisherOptions, studioOptions: try await studioOptions,
            personOptions: try await personOptions,
            contributionTypeOptions: try await contributionTypeOptions,
            canAddContributionType: canCreateVocabularyValue(user.roles),
            propertyNameOptions: try await propertyNameOptions,
            canAddPropertyName: canCreateVocabularyValue(user.roles),
            formatOptions: formatOptions, canSetFormat: canSetFormat),
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

  /// Contributor credits linking (task 8.2) - same full-replace semantics as
  /// `autosaveSessionAssociations`: each add/remove in the contributor dialog sends the
  /// *complete* resulting credit list, stored as an object array keyed `personId`/
  /// `contributionType` (matching what `LeafVolumeEditForm.init` reads back via
  /// `objectArrayField("credits")`).
  private struct AutosaveCreditsInput: Content {
    struct Credit: Content {
      let personId: String
      let contributionType: String
    }
    let credits: [Credit]
  }

  @Sendable
  func autosaveSessionCredits(req: Request) async throws -> Response {
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

    let input = try req.content.decode(AutosaveCreditsInput.self)
    session.fields["credits"] = .objectArray(
      input.credits.map { ["personId": $0.personId, "contributionType": $0.contributionType] })
    session.updatedAt = Date()
    try await req.editSessions.set(userID: user.sub, recordType: recordTypeVolume, session: session)

    return Response(status: .noContent)
  }

  /// Free-form property linking (task 9.2) - same full-replace semantics as
  /// `autosaveSessionCredits`, stored as an object array keyed `name`/`value` (matching what
  /// `LeafVolumeEditForm.init` reads back via `objectArrayField("properties")`).
  private struct AutosavePropertiesInput: Content {
    struct Property: Content {
      let name: String
      let value: String
    }
    let properties: [Property]
  }

  @Sendable
  func autosaveSessionProperties(req: Request) async throws -> Response {
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

    let input = try req.content.decode(AutosavePropertiesInput.self)
    session.fields["properties"] = .objectArray(
      input.properties.map { ["name": $0.name, "value": $0.value] })
    session.updatedAt = Date()
    try await req.editSessions.set(userID: user.sub, recordType: recordTypeVolume, session: session)

    return Response(status: .noContent)
  }

  /// Format selection (task 10.1) - editor/admin only, gated here (not just hidden client-side)
  /// so a crafted request from a submitter session can't set it either, per
  /// `volume-format-selector`'s spec: the whole field, not just growing its vocabulary, is
  /// editor/admin-only.
  private struct AutosaveFormatInput: Content {
    let format: String
  }

  @Sendable
  func autosaveSessionFormat(req: Request) async throws -> Response {
    guard let volumeID = req.parameters.get("volumeID") else {
      throw Abort(.badRequest)
    }
    guard let user = await req.currentUser, canCreateVocabularyValue(user.roles) else {
      throw Abort(.forbidden)
    }
    guard var session = await req.editSessions.get(userID: user.sub, recordType: recordTypeVolume),
      session.recordId == volumeID
    else {
      throw Abort(.notFound)
    }

    let input = try req.content.decode(AutosaveFormatInput.self)
    session.fields["format"] = .string(input.format)
    session.updatedAt = Date()
    try await req.editSessions.set(userID: user.sub, recordType: recordTypeVolume, session: session)

    return Response(status: .noContent)
  }

  /// Sample-image staging (task 11.2) - the browser uploads each new file directly to
  /// assets-web (`sample-staged/<userSub>-<n>`, same reasoning as cover staging: assets-web's
  /// auth only accepts browser-originated requests), then calls this with the *full* resulting
  /// staged-id list, same full-replace semantics as the other pickers. Written to `sampleAssetIds`
  /// directly (not `fields`) - it's part of `EditSession`'s own top-level schema, matching
  /// `stagedCoverAssetId`, not a `patchVolumeRequest`-shaped field.
  private struct AutosaveSamplesInput: Content {
    let sampleAssetIds: [String]
  }

  @Sendable
  func autosaveSessionSamples(req: Request) async throws -> Response {
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

    let input = try req.content.decode(AutosaveSamplesInput.self)
    session.sampleAssetIds = input.sampleAssetIds
    session.updatedAt = Date()
    try await req.editSessions.set(userID: user.sub, recordType: recordTypeVolume, session: session)

    return Response(status: .noContent)
  }

  /// Adds a new shared-vocabulary value (contribution type today) on behalf of the editor/admin
  /// contributor dialog's "add new" affordance (task 8.1/8.2) - a browser call can't carry the
  /// bearer token itself, so this forwards it server-to-server and returns the vocabulary's
  /// updated value list for the dialog's picker to pick up without a full page reload.
  private struct AddVocabularyValueInput: Content {
    let value: String
  }

  struct VocabularyValuesResponse: Content {
    let values: [String]
  }

  @Sendable
  func addVocabularyValue(req: Request) async throws -> VocabularyValuesResponse {
    guard let type = req.parameters.get("type") else {
      throw Abort(.badRequest)
    }
    guard let user = await req.currentUser, canCreateVocabularyValue(user.roles) else {
      throw Abort(.forbidden)
    }
    let input = try req.content.decode(AddVocabularyValueInput.self)
    let values = try await req.catalogAPI.addVocabularyValue(
      type: type, value: input.value, token: user.accessToken)
    return VocabularyValuesResponse(values: values)
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

  /// Case-insensitive substring match against `nameOf` a browse page's search query - the same
  /// in-memory filtering the existing volume browse page uses (these collections are small
  /// enough that no dedicated search endpoint is needed).
  private func filterByName<T>(_ items: [T], query: String?, nameOf: (T) -> String) -> [T] {
    guard let q = query, !q.isEmpty else { return items }
    let needle = q.lowercased()
    return items.filter { nameOf($0).lowercased().contains(needle) }
  }
}
