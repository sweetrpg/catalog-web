import Vapor

// These three clients are placeholders. Endpoint shapes for game-systems-api, profiles-api,
// and shelf-api (currently library-api - see sweetrpg/platform's rename-library-to-shelf
// change) aren't confirmed yet, so pages that would use them show a "coming soon" state rather
// than calling a real endpoint. Replace each method body with a real call once its backend
// contract is settled - the call sites (Controllers) already expect this shape, so filling
// these in shouldn't require touching the views.

struct ShelfAPIClient {
  let request: Request

  /// Per-user shelf entries (want/playing/played/owned + rating + review). Backed by
  /// library-api today, pending its rename to shelf-api.
  func fetchShelf(userID: String) async throws -> [String: String] {
    [:]
  }
}

extension Request {
  var shelfAPI: ShelfAPIClient { ShelfAPIClient(request: self) }
}
