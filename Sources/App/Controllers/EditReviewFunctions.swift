import CatalogAPIClient
import Crypto
import Foundation
import Vapor

// MARK: - Shared edit/review implementation

/// Fetches pending proposed changes for (path, recordID) when the session can review them -
/// mirrors CatalogController.detail's inline proposal-fetch block, factored out since all
/// four entity types share it. Fails open (nil) on any fetch error, matching that same
/// fail-open contract, since a review-fetch failure must degrade to "no pending changes
/// shown" rather than breaking the whole detail page for every editor/admin viewer.
func buildReview(
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

struct AcceptInput: Content {
  let mode: String
  let fields: [String]?
}

func acceptProposal(req: Request, path: String) async throws -> Response {
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

struct RejectInput: Content {
  let note: String?
}

func rejectProposal(req: Request, path: String) async throws -> Response {
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
