import AdminAPIClient
import CatalogAPIClient
import Foundation
import Redis
import Testing
import VaporTesting

@testable import App

@Suite("MaintenanceMode")
struct MaintenanceModeTests {
  // MARK: - MaintenanceModeMiddleware

  /// `AdminAPIClient.AdminClient` makes real `URLSession` calls - there's no request-level
  /// stubbing point - so exercising "admin-api reports an active maintenance-mode record"
  /// needs an actual bound HTTP server standing in for admin-api, not a mock. A fixed port
  /// keeps this simple; these tests run serially against it (Swift Testing still runs
  /// `@Suite` tests in one struct concurrently by default, but nothing else in this file binds
  /// this port).
  @discardableResult
  private func withFakeAdminAPI<T>(
    port: Int,
    maintenanceModesJSON: String,
    _ test: () async throws -> T
  ) async throws -> T {
    // Not `.testing` - that preset sanitizes `ProcessInfo.processInfo.arguments`, which under
    // `swift test` includes flags like `--test-bundle-path` that Vapor's own sanitizer doesn't
    // recognize and `startup()`'s command parser then rejects. A real bound listener (unlike
    // the app-under-test, which never calls `startup()` and instead uses `.testing()`'s
    // in-memory transport) needs `startup()` to actually run the serve command, so the
    // environment's arguments must be the app's own, not the test runner's.
    let fake = try await Application.make(Environment(name: "testing", arguments: ["vapor"]))
    fake.http.server.configuration.hostname = "127.0.0.1"
    fake.http.server.configuration.port = port
    fake.get("maintenance-modes", "active") { _ -> Response in
      Response(
        status: .ok, headers: ["content-type": "application/json"],
        body: .init(string: maintenanceModesJSON))
    }
    do {
      try await fake.startup()
    } catch {
      try? await fake.asyncShutdown()
      throw error
    }

    let result: T
    do {
      result = try await test()
    } catch {
      try? await fake.asyncShutdown()
      throw error
    }
    try await fake.asyncShutdown()
    return result
  }

  @discardableResult
  private func withMaintenanceModeApp<T>(
    adminAPIURL: String?,
    _ test: (Application) async throws -> T
  ) async throws -> T {
    try await withApp { app in
      app.views.use(.leaf)
      app.backendConfig = BackendConfig(
        catalogAPIURL: "unused", gameSystemsAPIURL: "unused", profilesAPIURL: "unused",
        shelfAPIURL: "unused", adminAPIURL: adminAPIURL)
      app.middleware.use(MaintenanceModeMiddleware())
      app.get("test-home") { req async throws -> View in
        try await req.view.render(
          "home",
          HomeContext(
            statCards: [], tagCloud: [], user: nil,
            meta: await PageMeta.make(req)))
      }
      return try await test(app)
    }
  }

  @Test("renders the maintenance page when an active maintenance-mode record exists")
  func maintenancePageRendersWhenActive() async throws {
    let port = 18761
    try await withFakeAdminAPI(
      port: port,
      maintenanceModesJSON: """
        [{
          "scope_type": "platform",
          "scope_value": "",
          "label": "Scheduled downtime",
          "description": "Upgrading the database.",
          "starts_at": "2026-08-01T00:00:00Z",
          "ends_at": "2026-08-01T04:00:00Z"
        }]
        """
    ) {
      try await withMaintenanceModeApp(adminAPIURL: "http://127.0.0.1:\(port)") { app in
        try await app.testing().test(.GET, "test-home") { res in
          #expect(res.status == .serviceUnavailable)
          #expect(res.body.string.contains("Scheduled downtime"))
          #expect(res.body.string.contains("Upgrading the database."))
          #expect(!res.body.string.contains("Vol. count"))
        }
      }
    }
  }

  @Test("renders the normal page when no maintenance-mode record is active")
  func normalPageRendersWhenNoMaintenance() async throws {
    let port = 18762
    try await withFakeAdminAPI(port: port, maintenanceModesJSON: "[]") {
      try await withMaintenanceModeApp(adminAPIURL: "http://127.0.0.1:\(port)") { app in
        try await app.testing().test(.GET, "test-home") { res in
          #expect(res.status == .ok)
          #expect(res.body.string.contains("Catalog Summary"))
        }
      }
    }
  }

  @Test("renders the normal page when admin-api is unreachable")
  func normalPageRendersWhenAdminAPIUnreachable() async throws {
    try await withMaintenanceModeApp(adminAPIURL: "http://127.0.0.1:1") { app in
      try await app.testing().test(.GET, "test-home") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains("Catalog Summary"))
      }
    }
  }
}
