import AdminAPIClient
import Redis
import Testing
import VaporTesting

@testable import App

@Suite("App")
struct AppTests {
  @Test("status ping responds ok")
  func statusPing() async throws {
    try await withApp(configure: configure) { app in
      try await app.testing().test(.GET, "status/ping") { res in
        #expect(res.status == .ok)
      }
    }
  }

  // These two exercise AdminClient directly against a minimal app (no full `configure(_:)` -
  // that bootstraps the global Swift Metrics backend, which can only happen once per process,
  // and Swift Testing runs tests concurrently by default) - just enough app setup for
  // `req.adminClient` to work: a route and, where needed, an overridden `backendConfig`.

  @Test("AdminClient returns no banners when ADMIN_API_URL is unset")
  func adminClientDisabledByDefault() async throws {
    try await withApp { app in
      app.get("test-banners") { req async -> [LeafBanner] in
        await req.adminClient.fetchBanners(scopes: ["platform"]).map(LeafBanner.init)
      }
      try await app.testing().test(.GET, "test-banners") { res in
        #expect(res.status == .ok)
        let banners = try res.content.decode([LeafBanner].self)
        #expect(banners.isEmpty)
      }
    }
  }

  @Test("AdminClient fails open when admin-api is unreachable")
  func adminClientFailsOpenOnUnreachableHost() async throws {
    try await withApp { app in
      app.backendConfig = BackendConfig(
        catalogAPIURL: "unused", gameSystemsAPIURL: "unused", profilesAPIURL: "unused",
        shelfAPIURL: "unused", adminAPIURL: "http://127.0.0.1:1")
      app.get("test-banners") { req async -> [LeafBanner] in
        await req.adminClient.fetchBanners(scopes: ["platform"]).map(LeafBanner.init)
      }
      try await app.testing().test(.GET, "test-banners") { res in
        #expect(res.status == .ok)
        let banners = try res.content.decode([LeafBanner].self)
        #expect(banners.isEmpty)
      }
    }
  }

  // Mirrors the two above: no full `configure(_:)`, just enough for `req.currentUser` to work.

  @Test("currentUser reads nil when the shared session Redis isn't configured")
  func currentUserDisabledByDefault() async throws {
    try await withApp { app in
      app.get("test-current-user") { req async -> String in
        (await req.currentUser)?.name ?? "nobody"
      }
      try await app.testing().test(.GET, "test-current-user") { res in
        #expect(res.status == .ok)
        #expect(res.body.string == "nobody")
      }
    }
  }

  @Test("currentUser fails open when the shared session Redis is unreachable")
  func currentUserFailsOpenOnUnreachableHost() async throws {
    try await withApp { app in
      app.redis(.sharedSession).configuration = try RedisConfiguration(
        hostname: "127.0.0.1", port: 1)
      app.sharedSessionRedisConfigured = true
      app.get("test-current-user") { req async -> String in
        (await req.currentUser)?.name ?? "nobody"
      }
      try await app.testing().test(
        .GET, "test-current-user",
        beforeRequest: { req in
          req.headers.add(name: .cookie, value: "\(sharedSessionCookieName)=some-session-id")
        }
      ) { res in
        #expect(res.status == .ok)
        #expect(res.body.string == "nobody")
      }
    }
  }

  // Renders a real Leaf template (not just a Swift-side compile check, since Leaf resolves
  // `#(meta.loginURL)` dynamically at render time) to confirm the header partial's login/logout
  // links interpolate correctly.

  @Test("header renders the log-in link when logged out")
  func headerRendersLogInLink() async throws {
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-home") { req async throws -> View in
        try await req.view.render(
          "home",
          HomeContext(
            volumeCount: 0, trending: [], tagCloud: [], user: nil,
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-home") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains(#"href="/auth/login?return_to=/test-home""#))
        #expect(!res.body.string.contains("Log Out"))
        #expect(!res.body.string.contains("avatar-menu-trigger"))
      }
    }
  }

  @Test("header renders the avatar menu without Admin for a non-admin session")
  func headerRendersAvatarMenuWithoutAdminForNonAdmin() async throws {
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-home") { req async throws -> View in
        try await req.view.render(
          "home",
          HomeContext(
            volumeCount: 0, trending: [], tagCloud: [],
            user: LeafUser(SessionUser(sub: "abc", name: "Alice", email: nil, roles: [])),
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-home") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains("avatar-menu-trigger"))
        #expect(res.body.string.contains(#"href="/users""#))
        #expect(!res.body.string.contains(#"href="/admin""#))
      }
    }
  }

  @Test("header renders a Gravatar image with an onerror fallback when the session has an email")
  func headerRendersGravatarImageWhenEmailPresent() async throws {
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-home") { req async throws -> View in
        try await req.view.render(
          "home",
          HomeContext(
            volumeCount: 0, trending: [], tagCloud: [],
            user: LeafUser(
              SessionUser(sub: "abc", name: "Alice", email: "alice@example.com", roles: [])),
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-home") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains("avatar-menu-avatar"))
        #expect(res.body.string.contains("https://www.gravatar.com/avatar/"))
        #expect(res.body.string.contains("d=404"))
        #expect(res.body.string.contains(#"onerror="this.style.display='none'""#))
        #expect(res.body.string.contains("avatar-menu-fallback"))
      }
    }
  }

  @Test("header renders only the fallback letter when the session has no email")
  func headerRendersOnlyFallbackWithoutEmail() async throws {
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-home") { req async throws -> View in
        try await req.view.render(
          "home",
          HomeContext(
            volumeCount: 0, trending: [], tagCloud: [],
            user: LeafUser(SessionUser(sub: "abc", name: "Alice", email: nil, roles: [])),
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-home") { res in
        #expect(res.status == .ok)
        #expect(!res.body.string.contains("avatar-menu-avatar"))
        #expect(res.body.string.contains("avatar-menu-fallback"))
      }
    }
  }

  @Test("header renders the Admin link for an admin session")
  func headerRendersAdminLinkForAdminSession() async throws {
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-home") { req async throws -> View in
        try await req.view.render(
          "home",
          HomeContext(
            volumeCount: 0, trending: [], tagCloud: [],
            user: LeafUser(SessionUser(sub: "abc", name: "Bob", email: nil, roles: ["admin"])),
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-home") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains(#"href="/admin""#))
        #expect(res.body.string.contains(#"href="/users""#))
      }
    }
  }

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
            volumeCount: 0, trending: [], tagCloud: [], user: nil,
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
          #expect(res.body.string.contains("Vol. count"))
        }
      }
    }
  }

  @Test("renders the normal page when admin-api is unreachable")
  func normalPageRendersWhenAdminAPIUnreachable() async throws {
    try await withMaintenanceModeApp(adminAPIURL: "http://127.0.0.1:1") { app in
      try await app.testing().test(.GET, "test-home") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains("Vol. count"))
      }
    }
  }
}
