import Foundation
import Tracing
import Vapor

/// Renders a maintenance page instead of the requested route whenever admin-api reports an
/// active maintenance-mode record for this app's scopes (`platform` or `service:catalog`) - see
/// sweetrpg/platform#15. Fail-open by construction: `AdminClient.fetchMaintenanceModes` never
/// throws (see the SDK's fail-open contract in `AdminClient.swift`), so any admin-api error,
/// timeout, or missing `ADMIN_API_URL` naturally yields an empty list and this middleware falls
/// through to the normal route - an unreachable admin-api must never take the whole site down.
///
/// Excludes `/status/ping` and `/metrics` - liveness probes and metrics scraping must keep
/// working during a maintenance window, or Kubernetes would restart otherwise-healthy pods.
struct MaintenanceModeMiddleware: AsyncMiddleware {
  private static let excludedPaths: Set<String> = ["/status/ping", "/metrics"]

  func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
    try await withSpan("middleware-maint-mode-respond") { _ in
      guard !Self.excludedPaths.contains(request.url.path) else {
        return try await next.respond(to: request)
      }

      let activeModes = await request.adminClient.fetchMaintenanceModes(
        scopes: ["platform", "service:catalog"])
      guard let active = activeModes.first else {
        return try await next.respond(to: request)
      }

      let view = try await request.view.render(
        "maintenance",
        MaintenanceContext(mode: LeafMaintenanceMode(active), meta: await PageMeta.make(request))
      )
      let response = try await view.encodeResponse(for: request).get()
      response.status = .serviceUnavailable
      return response
    }
  }
}

struct MaintenanceContext: Content {
  let mode: LeafMaintenanceMode
  let meta: PageMeta
}
