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
      app.get("test-banners") { req async -> [Banner] in
        await req.adminClient.fetchBanners(scopes: ["platform"])
      }
      try await app.testing().test(.GET, "test-banners") { res in
        #expect(res.status == .ok)
        let banners = try res.content.decode([Banner].self)
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
      app.get("test-banners") { req async -> [Banner] in
        await req.adminClient.fetchBanners(scopes: ["platform"])
      }
      try await app.testing().test(.GET, "test-banners") { res in
        #expect(res.status == .ok)
        let banners = try res.content.decode([Banner].self)
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
      }
    }
  }
}
