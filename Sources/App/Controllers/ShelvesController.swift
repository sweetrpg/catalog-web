import Vapor

/// "My Shelves" - per-user want/playing/played/owned lists. Backed by game-room-api, which
/// this app doesn't call yet (see `GameRoomAPIClient`), so this always renders the empty state
/// for now rather than a real shelf. Requires login once game-room-api is wired up; today it
/// just reflects whatever session exists.
struct ShelvesController: RouteCollection {
  func boot(routes: RoutesBuilder) throws {
    routes.get("shelves", use: index)
  }

  @Sendable
  func index(req: Request) async throws -> View {
    let user = await req.currentUser
    return try await req.view.render(
      "shelves",
      ShelvesContext(
        user: user.map(LeafUser.init),
        isLoggedIn: user != nil,
        meta: await PageMeta.make(req)
      ))
  }
}

struct ShelvesContext: Content {
  let user: LeafUser?
  let isLoggedIn: Bool
  let meta: PageMeta
}
