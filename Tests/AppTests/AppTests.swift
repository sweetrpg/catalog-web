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
}
