import Vapor

/// Builds Vapor's built-in CORSMiddleware from an ALLOWED_ORIGINS env var, matching the pattern
/// established in catalog-api (docs/service-conventions.md's CORS section): an explicit
/// comma-separated allowlist, never a wildcard, and no middleware registered at all if unset -
/// fail closed rather than defaulting to `*`.
///
/// This app is server-rendered, so most requests never need CORS headers at all (the browser
/// only enforces CORS on cross-origin fetches, and a page navigation to this app's own origin
/// isn't one). This matters for any client-side `fetch` calls this app's own JS makes back to
/// itself from a different origin (e.g. a CDN-hosted asset domain), and for any API routes this
/// app exposes that another origin might call directly.
enum CORSConfig {
  static func middleware() -> CORSMiddleware? {
    guard let originsEnv = Environment.get("ALLOWED_ORIGINS"), !originsEnv.isEmpty else {
      return nil
    }
    let origins = originsEnv.split(separator: ",").map(String.init)
    return CORSMiddleware(
      configuration: .init(
        allowedOrigin: .any(origins),
        allowedMethods: [.GET, .POST, .PUT, .PATCH, .DELETE, .OPTIONS],
        allowedHeaders: [.origin, .contentType, .accept, .authorization],
        allowCredentials: true
      ))
  }
}
