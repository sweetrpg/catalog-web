import CatalogAPIClient
import Foundation
import Testing
import VaporTesting

@testable import App

@Suite("Contribution counts")
struct ContributionCountTests {
  // CatalogAPIClientService reaches catalog-api over real HTTP through the SDK's own client,
  // which VaporTesting's in-memory transport can't intercept - so like withFakeAdminAPI, these
  // bind a minimal stand-in server and point an overridden backendConfig at it. Fixed,
  // suite-distinct ports keep the concurrently-run tests off each other's listeners.

  // Single line: the SDK's defensive decode-up-to-first-newline workaround for
  // sweetrpg/catalog-api#121 would otherwise see only `{"data": [` and fail.
  private static let contributionsJSON =
    #"{"data": [{"id": "c1", "type": "contributions", "attributes": {"role": "Author"}, "relationships": {"person": {"data": {"id": "p1", "type": "persons"}}, "volume": {"data": {"id": "v1", "type": "volumes"}}}}, {"id": "c2", "type": "contributions", "attributes": {"role": "Editor"}, "relationships": {"person": {"data": {"id": "p1", "type": "persons"}}, "volume": {"data": {"id": "v1", "type": "volumes"}}}}, {"id": "c3", "type": "contributions", "attributes": {"role": "Author"}, "relationships": {"person": {"data": {"id": "p1", "type": "persons"}}, "volume": {"data": {"id": "v2", "type": "volumes"}}}}, {"id": "c4", "type": "contributions", "attributes": {"role": "Author"}, "relationships": {"person": {"data": {"id": "p2", "type": "persons"}}, "volume": {"data": {"id": "v3", "type": "volumes"}}}}, {"id": "c5", "type": "contributions", "attributes": {"role": "Author"}, "relationships": {"volume": {"data": {"id": "v4", "type": "volumes"}}}}, {"id": "c6", "type": "contributions", "attributes": {"role": "Author"}, "relationships": {"person": {"data": {"id": "p3", "type": "persons"}}}}]}"#

  /// Binds a stand-in catalog-api serving the fixture at `/contributions`, runs `body` with an
  /// app whose backendConfig points at it, then shuts the stand-in down either way.
  private func withFakeCatalogAPI<T>(
    port: Int, _ body: (Application) async throws -> T
  ) async throws -> T {
    let fake = try await Application.make(Environment(name: "testing", arguments: ["vapor"]))
    fake.http.server.configuration.hostname = "127.0.0.1"
    fake.http.server.configuration.port = port
    fake.get("contributions") { _ -> Response in
      Response(
        status: .ok, headers: ["content-type": "application/vnd.api+json"],
        body: .init(string: Self.contributionsJSON))
    }
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
        profilesAPIURL: "unused", shelfAPIURL: "unused", adminAPIURL: nil)
      return try await body(app)
    }
  }

  @Test("multi-role credits on one volume count once")
  func countsDistinctVolumesNotRecords() async throws {
    try await withFakeCatalogAPI(port: 18_763) { app in
      app.get("test-counts") { req async throws -> [String: Int] in
        try await req.catalogAPI.fetchContributionCountsByPerson()
      }
      try await app.testing().test(.GET, "test-counts") { res in
        #expect(res.status == .ok)
        let counts = try res.content.decode([String: Int].self)
        // p1 is credited twice on v1 (author + editor) and once on v2 - two volumes.
        #expect(counts["p1"] == 2)
      }
    }
  }

  @Test("records missing a person or volume relationship are skipped")
  func skipsIncompleteRelationships() async throws {
    try await withFakeCatalogAPI(port: 18_764) { app in
      app.get("test-counts") { req async throws -> [String: Int] in
        try await req.catalogAPI.fetchContributionCountsByPerson()
      }
      try await app.testing().test(.GET, "test-counts") { res in
        #expect(res.status == .ok)
        let counts = try res.content.decode([String: Int].self)
        // c5 has no person, c6 has no volume - neither may surface anywhere.
        #expect(counts == ["p1": 2, "p2": 1])
      }
    }
  }

  @Test("persons with no credits are absent from the map")
  func omitsPersonsWithoutCredits() async throws {
    try await withFakeCatalogAPI(port: 18_765) { app in
      app.get("test-counts") { req async throws -> [String: Int] in
        try await req.catalogAPI.fetchContributionCountsByPerson()
      }
      try await app.testing().test(.GET, "test-counts") { res in
        #expect(res.status == .ok)
        let counts = try res.content.decode([String: Int].self)
        #expect(counts["p9"] == nil)
      }
    }
  }
}
