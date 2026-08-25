import Vapor

// These three clients are placeholders. Endpoint shapes for game-systems-api, profiles-api,
// and game-room-api (previously library-api, then shelf-api - see sweetrpg/platform's
// rename-shelf-to-game-room-service change) aren't confirmed yet, so pages that would use
// them show a "coming soon" state rather than calling a real endpoint. Replace each method
// body with a real call once its backend contract is settled - the call sites (Controllers)
// already expect this shape, so filling these in shouldn't require touching the views.

struct GameRoomAPIClient {
  let request: Request

  /// Per-user shelf entries (want/playing/played/owned + rating + review). Backed by
  /// game-room-api.
  func fetchGameRoom(userID: String) async throws -> [String: String] {
    [:]
  }
}

extension Request {
  var gameRoomAPI: GameRoomAPIClient { GameRoomAPIClient(request: self) }
}
