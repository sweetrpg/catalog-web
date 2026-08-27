import Vapor

// These three clients are placeholders. Endpoint shapes for game-systems-api, profiles-api,
// and game-room-api (previously library-api, then shelf-api - see sweetrpg/platform's rename-shelf-to-game-room-service
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

extension Request {
  var gameSystemsAPI: GameSystemsAPIClient { GameSystemsAPIClient(request: self) }
}
