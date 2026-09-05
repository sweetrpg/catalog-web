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
/// Roles that may bulk-create Person records - editor/admin only, narrower than
/// `editCapableRoles`'s single-entity "Add person" (which a submitter can also reach) per
/// catalog-entity-bulk-add's spec. Currently the same roles as `reviewCapableRoles`/
/// `vocabularyCreateCapableRoles`, kept separate for the same reason those are their own sets.
private let bulkAddCapableRoles: Set<String> = ["editor", "admin"]
/// Roles that may create a publisher/studio/person inline from the volume edit page's pickers
/// - editor/admin only, per add-entity-popup-volume-edit's design.md (narrower than
/// `editCapableRoles`, which also includes submitter; the standalone create pages remain
/// available to a submitter via `submitCreate`'s existing `canEdit` gate).
private let entityInlineCreateCapableRoles: Set<String> = ["editor", "admin"]

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

/// Adds a new shared-vocabulary value (contribution type, property name, license tag, ...) on
/// behalf of an editor/admin picker's "add new" affordance - a browser call can't carry the
/// bearer token itself, so this forwards it server-to-server and returns the vocabulary's
/// updated value list for the picker to pick up without a full page reload. Shared by
/// VolumesController and LicensesController's `edit/vocabulary/:type` routes rather than
/// duplicated per controller - the handler is generic over `type`, nothing volume- or
/// license-specific about it.
struct AddVocabularyValueInput: Content {
  let value: String
}

struct VocabularyValuesResponse: Content {
  let values: [String]
}

@Sendable
func addVocabularyValue(req: Request) async throws -> VocabularyValuesResponse {
  try await withSpan("add-vocabulary-value") { _ in
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
}

func canBulkAddPersons(_ roles: [String]) -> Bool {
  !Set(roles).isDisjoint(with: bulkAddCapableRoles)
}

func canCreateEntities(_ roles: [String]) -> Bool {
  !Set(roles).isDisjoint(with: entityInlineCreateCapableRoles)
}

/// Roles that may roll a record back to a past version - admin only per design.md's decision:
/// unlike `reviewCapableRoles`, an editor can create/accept/reject versions but not arbitrarily
/// rewind history.
private let rollbackCapableRoles: Set<String> = ["admin"]

func canRollback(_ roles: [String]) -> Bool {
  !Set(roles).isDisjoint(with: rollbackCapableRoles)
}

/// Roles that may soft-delete/restore a catalog entity - admin only (task 3.1's spec
/// requirement), same role set as `rollbackCapableRoles` (catalog-api gates both routes
/// identically) but its own named function since the two gate conceptually distinct actions.
func canDelete(_ roles: [String]) -> Bool {
  canRollback(roles)
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

/// Renders a raw Auth0 subject (`github|419457`) as a readable "provider #id" label for display
/// in version history/review UI - profiles-api isn't wired up yet (`ProfilesAPIClient.swift`),
/// so a real display name/username isn't available; this is a readability improvement over the
/// bare sub, not a stand-in for that lookup. A sub without a `|` (unexpected shape) is returned
/// unchanged.
func humanizeSubmitterID(_ sub: String) -> String {
  guard let pipeIndex = sub.firstIndex(of: "|") else { return sub }
  let provider = sub[sub.startIndex..<pipeIndex]
  let id = sub[sub.index(after: pipeIndex)...]
  return "\(provider) #\(id)"
}

/// Fetches pending (state: submitted) versions for (path, recordID) when the session can
/// review them - the version-model counterpart of the old proposed_changes-based
/// `buildReview`, generic over the entity type's own Version attributes since each type's
/// substantive fields differ. Fails open (nil) on any fetch error, matching
/// `VolumesController.detail`'s fail-open contract for the same review section on volumes - a
/// review-fetch failure must degrade to "no pending changes shown" rather than breaking the
/// whole detail page for every editor/admin viewer.
func buildReview<T: EntityVersionAttributes>(
  req: Request, path: String, recordID: String, fieldSpecs: [EntityFieldSpec],
  currentValues: [String: String], sessionUser: SessionUser?,
  versionFieldValues: (T) -> [String: String]
) async -> LeafEntityVersionReview? {
  await withSpan("review-build") { _ in
    let roles = sessionUser?.roles ?? []
    guard canReview(roles), let token = sessionUser?.accessToken else { return nil }
    do {
      let allVersions: [T] = try await req.catalogAPI.fetchEntityVersions(
        path: path, id: recordID, token: token)
      let pending = allVersions.filter { $0.state == "submitted" }
      guard !pending.isEmpty else { return nil }
      let selectedVersion = req.query[Int.self, at: "proposal"]
      let selected = pending.first { $0.version == selectedVersion } ?? pending[0]
      return LeafEntityVersionReview(
        recordID: recordID, currentValues: currentValues, pending: pending, selected: selected,
        fieldSpecs: fieldSpecs, versionFieldValues: versionFieldValues,
        locale: I18n.numberLocale(for: req))
    } catch {
      req.logger.warning(
        "failed to fetch pending versions for \(path)/\(recordID): \(error)")
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
    fields: fields.map { spec in
      let value = values[spec.key] ?? ""
      switch spec.kind {
      case .text:
        return LeafEntityFieldInput(
          key: spec.key, label: spec.label, value: value, isTextarea: false, isSelect: false,
          selectOptions: [])
      case .textarea:
        return LeafEntityFieldInput(
          key: spec.key, label: spec.label, value: value, isTextarea: true, isSelect: false,
          selectOptions: [])
      case .select(let options):
        return LeafEntityFieldInput(
          key: spec.key, label: spec.label, value: value, isTextarea: false, isSelect: true,
          selectOptions: options.map { LeafSelectOption(value: $0, isSelected: $0 == value) })
      }
    },
    user: LeafUser(user),
    meta: meta
  )
}

/// Builds a blank create form's context - same field list/kind as `makeEditContext`, empty
/// values, and a `submitPath`/`backPath` pointing at the collection (`/new`, the browse page)
/// instead of an existing record.
func makeCreateContext(
  basePath: String, fields: [EntityFieldSpec], user: SessionUser, meta: PageMeta
) -> EntityEditContext {
  EntityEditContext(
    id: "",
    backPath: basePath,
    submitPath: "\(basePath)/new",
    fields: fields.map { spec in
      switch spec.kind {
      case .text:
        return LeafEntityFieldInput(
          key: spec.key, label: spec.label, value: "", isTextarea: false, isSelect: false,
          selectOptions: [])
      case .textarea:
        return LeafEntityFieldInput(
          key: spec.key, label: spec.label, value: "", isTextarea: true, isSelect: false,
          selectOptions: [])
      case .select(let options):
        return LeafEntityFieldInput(
          key: spec.key, label: spec.label, value: "", isTextarea: false, isSelect: true,
          selectOptions: options.map { LeafSelectOption(value: $0, isSelected: false) })
      }
    },
    user: LeafUser(user),
    meta: meta
  )
}

/// Creates a publisher/studio/person/license - the generic counterpart of `submitEdit`.
/// Editor/admin/submitter, same gate as editing (`canEdit`); catalog-api always creates the
/// record live regardless of role (see sweetrpg/catalog-api#220 - there's no prior version to
/// submit a proposal against).
func submitCreate(req: Request, path: String, fields: [EntityFieldSpec]) async throws -> Response {
  try await withSpan("submit-create") { _ in
    guard let user = await req.currentUser, canEdit(user.roles) else { throw Abort(.forbidden) }

    let input = try req.content.decode([String: String].self)
    let known = Set(fields.map(\.key))
    let filtered = input.filter { known.contains($0.key) }

    let id = try await req.catalogAPI.createEntity(
      path: path, token: user.accessToken, fields: filtered)
    await req.catalogAPI.invalidateEntityListCache(path: path)

    return req.redirect(to: "\(req.basePath)\(path)/\(id)")
  }
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
      // Only .applied changes the live record's display name - a .proposed submitter edit
      // hasn't touched it yet, so the list-cache entry is still accurate.
      await req.catalogAPI.invalidateEntityListCache(path: path)
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

func acceptVersionReview(req: Request, path: String) async throws -> Response {
  try await withSpan("accept-version-review") { _ in
    guard let id = req.parameters.get("id"), let versionParam = req.parameters.get("version"),
      let version = Int(versionParam)
    else {
      throw Abort(.badRequest)
    }
    guard let user = await req.currentUser, canReview(user.roles) else { throw Abort(.forbidden) }
    let input = try req.content.decode(AcceptInput.self)
    let fields: [String]? = input.mode == "all" ? nil : (input.fields ?? [])

    let result = try await req.catalogAPI.acceptEntityVersion(
      path: path, id: id, version: version, token: user.accessToken, fields: fields)

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

func rejectVersionReview(req: Request, path: String) async throws -> Response {
  try await withSpan("reject-version-review") { _ in
    guard let id = req.parameters.get("id"), let versionParam = req.parameters.get("version"),
      let version = Int(versionParam)
    else {
      throw Abort(.badRequest)
    }
    guard let user = await req.currentUser, canReview(user.roles) else { throw Abort(.forbidden) }
    let input = try req.content.decode(RejectInput.self)

    _ = try await req.catalogAPI.rejectEntityVersion(
      path: path, id: id, version: version, token: user.accessToken, note: input.note)

    return req.redirect(to: "\(req.basePath)\(path)/\(id)")
  }
}
