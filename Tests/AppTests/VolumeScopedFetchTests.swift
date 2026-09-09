import CatalogAPIClient
import Foundation
import Testing
import VaporTesting

@testable import App

@Suite("Volume-scoped credits and reviews")
struct VolumeScopedFetchTests {
  // fetchCredits/fetchReviews now call catalog-api's volume-scoped routes
  // (/volumes/:id/contributions, /volumes/:id/reviews) instead of pulling whole collections.
  // Like ContributionCountTests, these bind a stand-in catalog-api on a fixed port because the
  // SDK's HTTP client isn't interceptable by VaporTesting's in-memory transport.

  private static let contributionsJSON =
    #"{"data": [{"id": "c1", "type": "contributions", "attributes": {"role": "Author"}, "relationships": {"person": {"data": {"id": "p1", "type": "persons"}}, "volume": {"data": {"id": "v1", "type": "volumes"}}}}, {"id": "c2", "type": "contributions", "attributes": {"role": "Editor"}, "relationships": {"person": {"data": {"id": "p2", "type": "persons"}}, "volume": {"data": {"id": "v1", "type": "volumes"}}}}]}"#

  private static let reviewsJSON =
    #"{"data": [{"id": "r1", "type": "reviews", "attributes": {"author": "Ann", "rating": 4.6, "body": "Great book"}, "relationships": {"volume": {"data": {"id": "v1", "type": "volumes"}}}}]}"#

  private static let personsJSON =
    #"{"data": [{"id": "p1", "type": "persons", "attributes": {"name": "Ann Author"}}, {"id": "p2", "type": "persons", "attributes": {"name": "Ed Editor"}}]}"#

  private func withFakeCatalogAPI<T>(
    port: Int, _ body: (Application) async throws -> T
  ) async throws -> T {
    let fake = try await Application.make(Environment(name: "testing", arguments: ["vapor"]))
    fake.http.server.configuration.hostname = "127.0.0.1"
    fake.http.server.configuration.port = port
    let json = { (s: String) in
      Response(
        status: .ok, headers: ["content-type": "application/vnd.api+json"], body: .init(string: s))
    }
    fake.get("volumes", ":id", "contributions") { _ in json(Self.contributionsJSON) }
    fake.get("volumes", ":id", "reviews") { _ in json(Self.reviewsJSON) }
    fake.get("persons") { _ in json(Self.personsJSON) }
    do {
      try await fake.startup()
    } catch {
      try? await fake.asyncShutdown()
      throw error
    }
    defer { Task { try? await fake.asyncShutdown() } }
    return try await withApp { app in
      app.backendConfig = BackendConfig(
        catalogAPIURL: "http://127.0.0.1:\(port)", gameSystemsAPIURL: "unused",
        profilesAPIURL: "unused", gameRoomAPIURL: "unused", adminAPIURL: nil,
        volumeTagsLimit: 20)
      return try await body(app)
    }
  }

  @Test("fetchCredits resolves person names from the scoped contributions route")
  func creditsFromScopedRoute() async throws {
    try await withFakeCatalogAPI(port: 18_781) { app in
      app.get("test-credits") { req async throws -> [String] in
        try await req.catalogAPI.fetchCredits(volumeID: "v1").map { "\($0.role):\($0.person)" }
      }
      try await app.testing().test(.GET, "test-credits") { res in
        #expect(res.status == .ok)
        let rows = try res.content.decode([String].self)
        #expect(rows == ["Author:Ann Author", "Editor:Ed Editor"])
      }
    }
  }

  @Test("fetchReviews maps the scoped reviews route")
  func reviewsFromScopedRoute() async throws {
    try await withFakeCatalogAPI(port: 18_782) { app in
      app.get("test-reviews") { req async throws -> [String] in
        try await req.catalogAPI.fetchReviews(volumeID: "v1").map {
          "\($0.author)|\($0.rating)|\($0.text)"
        }
      }
      try await app.testing().test(.GET, "test-reviews") { res in
        #expect(res.status == .ok)
        let rows = try res.content.decode([String].self)
        #expect(rows == ["Ann|5|Great book"])
      }
    }
  }
}
