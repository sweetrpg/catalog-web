import AdminAPIClient
import CatalogAPIClient
import Foundation
import Redis
import Testing
import VaporTesting

@testable import App

@Suite("Status")
struct StatusTests {
  @Test("status ping responds ok and reports the build version")
  func statusPing() async throws {
    try await withApp(configure: configure) { app in
      try await app.testing().test(.GET, "status/ping") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains(#""version":"dev""#))
      }
    }
  }
}
