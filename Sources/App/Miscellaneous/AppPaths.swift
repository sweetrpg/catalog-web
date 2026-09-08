import Vapor

/// The path prefix Traefik strips before forwarding a request to this app (see
/// kubernetes/overlays/*/middlewares.yaml) - e.g. `/catalog` in dev. Every internal link, form
/// action, and redirect this app generates needs to prepend this, or the browser's next request
/// won't round-trip back through the ingress's path-based routing. Empty in local development,
/// where there's no reverse proxy stripping anything.
extension Request {
  var basePath: String {
    Environment.get("INGRESS_BASE_PATH") ?? ""
  }

  /// Where the SweetRPG logo links out to - the platform's root site, not this app's own home
  /// page. Differs per environment (e.g. https://dev.sweetrpg.com/ in dev), so it's an env var
  /// rather than a constant. Falls back to "/" (this app's own root) if unset, matching the old
  /// behavior rather than producing a dead link in an environment that hasn't set it yet.
  var rootURL: String {
    Environment.get("ROOT_URL") ?? "/"
  }

  /// Base URL for shared frontend static assets (logo, favicon, stylesheet), served from
  /// shared-web rather than this app's own Public/ - see docs/frontend-conventions.md in
  /// sweetrpg/platform. Differs per environment (e.g. https://dev.sweetrpg.com/shared in dev).
  /// Falls back to a local assets-web instance's own address, so a developer running catalog-web
  /// alone still sees a rendered logo/stylesheet rather than a broken reference.
  var sharedURL: String {
    Environment.get("SHARED_URL") ?? "http://localhost:8081"
  }

  /// Base URL for catalog assets (book covers, samples, etc.)
  var assetsURL: String {
    Environment.get("ASSETS_URL") ?? "http://localhost:8081"
  }

  /// Base URL (host + path prefix) for `game-systems-web`, used to build the volume detail
  /// page's System-section links out to each referenced game system's detail page. Differs per
  /// environment (e.g. https://dev.sweetrpg.com/game-systems in dev, where game-systems-web
  /// serves under `/game-systems` on the shared host). Falls back to a locally-run
  /// game-systems-web instance's own address so a developer running catalog-web alone still
  /// gets a resolvable link rather than a dead one. Never a call to game-systems-api - the
  /// link is built entirely from this base URL and the volume's stored system reference id.
  var gameSystemsWebURL: String {
    Environment.get("GAME_SYSTEMS_WEB_URL") ?? "http://localhost:8082"
  }
}
