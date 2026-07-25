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

  /// Redirects to a path on this app itself (e.g. "/login"), prefixed with `basePath`. Use
  /// this instead of `redirect(to:)` for any in-app redirect target - `redirect(to:)` is still
  /// correct as-is for external URLs (e.g. Auth0's own domain), which must not be prefixed.
  func redirectLocal(to path: String) -> Response {
    redirect(to: basePath + path)
  }
}
