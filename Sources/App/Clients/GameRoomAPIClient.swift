import Vapor

/// Whether a volume is in a visitor's game-room-api library - `.unavailable` covers any
/// transport/decode failure, kept distinct from `.absent` so a caller can show "can't tell
/// right now" instead of a false "not in your library" (see design.md's fail-open decision).
enum LibraryMembership: Sendable {
  case present
  case absent
  case unavailable
}

/// Thin wrapper around game-room-api's library endpoints (previously library-api, then
/// shelf-api - see sweetrpg/platform's rename-shelf-to-game-room-service change). No SDK
/// exists for game-room-api today, so this calls `request.client` directly, same rationale as
/// `CatalogAPIClientService`'s raw-client calls for routes the `catalog-api-client.swift` SDK
/// doesn't cover.
struct GameRoomAPIClient {
  let request: Request

  private struct LibraryEntry: Codable {
    let volumeId: String
    enum CodingKeys: String, CodingKey {
      case volumeId = "volume_id"
    }
  }

  /// game-room-api's `GET /users/:user_id/library` response - only the one field this client
  /// needs. The endpoint always returns 200 with an empty `entries` array for a user with no
  /// library yet (game-room-api synthesizes one rather than 404ing), so "doesn't exist yet"
  /// and "exists but doesn't contain this volume" are already the same wire shape - no special
  /// casing needed here for design.md's "brand-new user" risk.
  private struct LibraryResponse: Codable {
    let entries: [LibraryEntry]
  }

  /// Fetches the visitor's whole library and checks it for `volumeID` client-side, mirroring
  /// game-room-web's own Library page (fetch once, filter in memory) rather than asking
  /// game-room-api for a new per-volume endpoint - see design.md. A library is bounded by what
  /// one user owns, not by catalog size, so this stays cheap. Throws on any transport/decode
  /// failure; callers map that to `.unavailable` and fail open rather than breaking the page.
  func isInLibrary(userID: String, volumeID: String, token: String) async throws -> Bool {
    let uri = URI(string: request.backendConfig.gameRoomAPIURL + "/users/\(userID)/library")
    let response = try await request.client.get(uri) { clientReq in
      clientReq.headers.bearerAuthorization = BearerAuthorization(token: token)
    }
    guard response.status == .ok else {
      throw Abort(response.status, reason: "game-room-api library fetch failed")
    }
    let library = try response.content.decode(LibraryResponse.self)
    return library.entries.contains { $0.volumeId == volumeID }
  }

  /// Links `volumeID` into `userID`'s library via `POST /users/:user_id/library/entries`.
  func addLibraryEntry(userID: String, volumeID: String, token: String) async throws {
    let uri = URI(string: request.backendConfig.gameRoomAPIURL + "/users/\(userID)/library/entries")
    let response = try await request.client.post(uri) { clientReq in
      clientReq.headers.bearerAuthorization = BearerAuthorization(token: token)
      try clientReq.content.encode(["volume_id": volumeID], as: .json)
    }
    guard response.status == .ok else {
      throw Abort(response.status, reason: "game-room-api add library entry failed")
    }
  }

  /// Unlinks `volumeID` from `userID`'s library via
  /// `DELETE /users/:user_id/library/entries/:volume_id`.
  func removeLibraryEntry(userID: String, volumeID: String, token: String) async throws {
    let uri = URI(
      string: request.backendConfig.gameRoomAPIURL + "/users/\(userID)/library/entries/\(volumeID)")
    let response = try await request.client.delete(uri) { clientReq in
      clientReq.headers.bearerAuthorization = BearerAuthorization(token: token)
    }
    guard response.status == .ok else {
      throw Abort(response.status, reason: "game-room-api remove library entry failed")
    }
  }
}

extension Request {
  var gameRoomAPI: GameRoomAPIClient { GameRoomAPIClient(request: self) }
}
