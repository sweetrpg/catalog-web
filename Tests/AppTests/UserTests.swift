import AdminAPIClient
import CatalogAPIClient
import Foundation
import Redis
import Testing
import VaporTesting

@testable import App

@Suite("User")
struct UserTests {

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

  @Test("SessionUser decodes auth-web's RFC 3339 expiry, not a raw Double")
  func sessionUserDecodesRFC3339Expiry() throws {
    // Exactly the shape auth-web's SessionUserAccess now writes (see auth-web's
    // fix/session-expiry-iso8601) - docs/frontend-conventions.md's "Shared session schema"
    // documents `expiry` as an RFC 3339 string, not the raw Double a plain JSONDecoder's
    // .deferredToDate default would expect.
    let json = """
      {"sub":"auth0|abc","name":"Ada","email":"ada@example.com","roles":["admin"],\
      "accessToken":"token","expiry":"2027-01-15T08:00:00Z"}
      """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let user = try decoder.decode(SessionUser.self, from: Data(json.utf8))
    #expect(user.name == "Ada")
    #expect(user.expiry.timeIntervalSince1970 == 1_800_000_000)
  }
}
