import AdminAPIClient
import CatalogAPIClient
import Foundation
import Redis
import Testing
import VaporTesting

@testable import App

@Suite("AdminClient")
struct AdminClientTests {
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
        gameRoomAPIURL: "unused", adminAPIURL: "http://127.0.0.1:1")
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
}
