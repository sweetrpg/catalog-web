import CatalogAPIClient
import Crypto
import Foundation
import Tracing
import Vapor

// MARK: - Shared edit/review implementation

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
/// Roles that may add a new value to a shared vocabulary (contribution type today; property
/// name/format in later task groups) - editor/admin only, per design.md's decision that a
/// submitter can use an existing vocabulary value but never grow the list. Currently the same
/// roles as `coverUploadCapableRoles`, kept separate for the same reason that one is its own set.
private let vocabularyCreateCapableRoles: Set<String> = ["editor", "admin"]

func canEdit(_ roles: [String]) -> Bool {
  !Set(roles).isDisjoint(with: editCapableRoles)
}

func canReview(_ roles: [String]) -> Bool {
  !Set(roles).isDisjoint(with: reviewCapableRoles)
}

func canUploadCover(_ roles: [String]) -> Bool {
  !Set(roles).isDisjoint(with: coverUploadCapableRoles)
}

func canCreateVocabularyValue(_ roles: [String]) -> Bool {
  !Set(roles).isDisjoint(with: vocabularyCreateCapableRoles)
}

/// Roles that may roll a record back to a past version - admin only per design.md's decision:
/// unlike `reviewCapableRoles`, an editor can create/accept/reject versions but not arbitrarily
/// rewind history.
private let rollbackCapableRoles: Set<String> = ["admin"]

func canRollback(_ roles: [String]) -> Bool {
  !Set(roles).isDisjoint(with: rollbackCapableRoles)
}

/// The only `recordType` the durable edit-session mechanism supports today - see
/// docs/frontend-conventions.md's edit-session schema in sweetrpg/platform.
let recordTypeVolume = "volume"

/// A user's raw Auth0 subject (e.g. `auth0|abc123`, `google-oauth2|123456`) is not a valid
/// assets-web asset id - `|` doesn't survive Werkzeug's `secure_filename`, and assets-web
/// rejects any id that comes back changed. Staged assets are filed under this sanitized form
/// instead (`cover-staged/<sanitized>`) - purely a frontend convention: catalog-api's
/// `editsession`/`proposedchanges` packages treat a staged asset id as an opaque string and
/// never reconstruct it from the sub themselves, so as long as the upload path and the id
/// recorded in the session agree (both computed here), the rest of the system doesn't need to
/// know or care about this sanitization.
func sanitizedAssetUserID(_ sub: String) -> String {
  sub.replacingOccurrences(of: "|", with: "-")
}

/// Fetches pending proposed changes for (path, recordID) when the session can review them -
/// mirrors CatalogController.detail's inline proposal-fetch block, factored out since all
/// four entity types share it. Fails open (nil) on any fetch error, matching that same
/// fail-open contract, since a review-fetch failure must degrade to "no pending changes
/// shown" rather than breaking the whole detail page for every editor/admin viewer.
func buildReview(
  req: Request, path: String, recordID: String, fieldSpecs: [EntityFieldSpec],
  sessionUser: SessionUser?
) async -> LeafEntityProposalReview? {
  await withSpan("review-build") { _ in
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
}

func makeEditContext(
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

func submitEdit(req: Request, path: String, fields: [EntityFieldSpec]) async throws
  -> Response
{
  try await withSpan("submit-edit") { _ in
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
}

struct AcceptInput: Content {
  let mode: String
  let fields: [String]?
}

func acceptProposal(req: Request, path: String) async throws -> Response {
  try await withSpan("accept-proposal") { _ in
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
}

struct RejectInput: Content {
  let note: String?
}

func rejectProposal(req: Request, path: String) async throws -> Response {
  try await withSpan("reject-proposal") { _ in
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
}
