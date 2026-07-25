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
    Environment.get("SWEETRPG_ROOT_URL") ?? "/"
  }

  /// Redirects to a path on this app itself (e.g. "/login"), prefixed with `basePath`. Use
  /// this instead of `redirect(to:)` for any in-app redirect target - `redirect(to:)` is still
  /// correct as-is for external URLs (e.g. Auth0's own domain), which must not be prefixed.
  func redirectLocal(to path: String) -> Response {
    redirect(to: basePath + path)
  }
}
