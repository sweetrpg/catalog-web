import Vapor

/// "My Shelves" - the signed-in user's game-room-api library. Wishlists and want/playing/played
/// lists are not modeled by game-room-api yet (only library entries and wishlists exist), so
/// this page shows library entries only.
struct ShelvesController: RouteCollection {
  func boot(routes: RoutesBuilder) throws {
    routes.get("shelves", use: index)
  }

  @Sendable
  func index(req: Request) async throws -> View {
    let user = await req.currentUser
    var entries: [LeafShelfEntry] = []
    var unavailable = false
    if let user {
      do {
        entries = try await req.gameRoomAPI.fetchShelfEntries(
          userID: user.sub, token: user.accessToken
        ).map(LeafShelfEntry.init)
      } catch {
        req.logger.warning("shelves: failed to load library for \(user.sub): \(error)")
        unavailable = true
      }
    }
    return try await req.view.render(
      "shelves",
      ShelvesContext(
        user: user.map(LeafUser.init),
        isLoggedIn: user != nil,
        unavailable: unavailable,
        entries: entries,
        meta: await PageMeta.make(req)
      ))
  }
}

struct LeafShelfEntry: Content {
  let volumeID: String
  /// Empty when game-room-api has no title snapshot; the template shows a localized fallback.
  let title: String
  let hasTitle: Bool

  init(_ entry: GameRoomAPIClient.ShelfEntry) {
    volumeID = entry.volumeID
    title = entry.title
    hasTitle = !entry.title.isEmpty
  }
}

struct ShelvesContext: Content {
  let user: LeafUser?
  let isLoggedIn: Bool
  let unavailable: Bool
  let entries: [LeafShelfEntry]
  let meta: PageMeta
}
