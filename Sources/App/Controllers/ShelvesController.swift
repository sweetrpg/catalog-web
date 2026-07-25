import Vapor

/// "My Shelves" - per-user want/playing/played/owned lists. Backed by shelf-api (currently
/// library-api), which this app doesn't call yet (see `ShelfAPIClient`), so this always renders
/// the empty state for now rather than a real shelf. Requires login once shelf-api is wired up;
/// today it just reflects whatever session exists.
struct ShelvesController: RouteCollection {
  func boot(routes: RoutesBuilder) throws {
    routes.get("shelves", use: index)
  }

  @Sendable
  func index(req: Request) async throws -> View {
    let user = req.currentUser
    return try await req.view.render(
      "shelves",
      ShelvesContext(
        user: user.map(LeafUser.init),
        isLoggedIn: user != nil,
        meta: PageMeta(req)
      ))
  }
}

struct ShelvesContext: Content {
  let user: LeafUser?
  let isLoggedIn: Bool
  let meta: PageMeta
}
