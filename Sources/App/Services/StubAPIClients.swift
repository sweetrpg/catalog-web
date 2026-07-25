import Vapor

// These three clients are placeholders. Endpoint shapes for game-systems-api, profiles-api,
// and shelf-api (currently library-api - see sweetrpg/platform's rename-library-to-shelf
// change) aren't confirmed yet, so pages that would use them show a "coming soon" state rather
// than calling a real endpoint. Replace each method body with a real call once its backend
// contract is settled - the call sites (Controllers) already expect this shape, so filling
// these in shouldn't require touching the views.

struct GameSystemsAPIClient {
  let request: Request

  /// Richer game-system detail than catalog-api's own shallow `/systems` list.
  /// - Returns: `nil` until this is wired up - callers should render a placeholder, not treat
  ///   `nil` as an error.
  func fetchSystemDetail(id: String) async throws -> String? {
    nil
  }
}

struct ProfilesAPIClient {
  let request: Request

  /// User account/profile info once accounts are wired through Auth0 + profiles-api.
  func fetchProfile(userID: String) async throws -> String? {
    nil
  }
}

struct ShelfAPIClient {
  let request: Request

  /// Per-user shelf entries (want/playing/played/owned + rating + review). Backed by
  /// library-api today, pending its rename to shelf-api.
  func fetchShelf(userID: String) async throws -> [String: String] {
    [:]
  }
}

extension Request {
  var gameSystemsAPI: GameSystemsAPIClient { GameSystemsAPIClient(request: self) }
  var profilesAPI: ProfilesAPIClient { ProfilesAPIClient(request: self) }
  var shelfAPI: ShelfAPIClient { ShelfAPIClient(request: self) }
}
