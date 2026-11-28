import CatalogAPIClient
import Foundation
import Testing
import VaporTesting

@testable import App

@Suite("Tag filter")
struct TagFilterTests {
  // Binds a stand-in catalog-api on a fixed port, as VolumeScopedFetchTests does. It echoes the
  // volume list's raw query back as a volume title so the test can see what was sent.
  @Test("browsing by tag filters on tags.name and escapes reserved characters")
  func browseByTagSendsEscapedName() async throws {
    let fake = try await Application.make(Environment(name: "testing", arguments: ["vapor"]))
    fake.http.server.configuration.hostname = "127.0.0.1"
    fake.http.server.configuration.port = 18_841
    let json = { (s: String) in
      Response(
        status: .ok, headers: ["content-type": "application/vnd.api+json"], body: .init(string: s))
    }
    fake.get("volumes") { req in
      json(
        #"{"data": [{"id": "v1", "type": "volumes", "attributes": {"title": "\#(req.url.query ?? "")"}}]}"#
      )
    }
    for path in ["publishers", "studios", "licenses"] {
      fake.get(.constant(path)) { _ in json(#"{"data": []}"#) }
    }
    try await fake.startup()
    defer { Task { try? await fake.asyncShutdown() } }

    try await withApp { app in
      app.backendConfig = BackendConfig(
        catalogAPIURL: "http://127.0.0.1:18841", gameSystemsAPIURL: "unused",
        profilesAPIURL: "unused", gameRoomAPIURL: "unused", adminAPIURL: nil,
        volumeTagsLimit: 20)
      app.get("test-browse") { req async throws -> String in
        try await req.catalogAPI.browseVolumes(q: nil, tag: "D&D, 5e+#=", page: 1).items[0].title
      }
      try await app.testing().test(.GET, "test-browse") { res in
        #expect(
          res.body.string
            == "filter%5Btags.name%5D=D%26D%2C%205e%2B%23%3D&page%5Bstart%5D=0&page%5Blimit%5D=30")
      }
    }
  }

  @Test("pager links escape reserved characters in the tag")
  func pagerEscapesTag() {
    let pagination = makePagination(
      totalCount: 1000, page: 1, basePath: "", path: "/browse", query: ["tag": "D&D+"])
    #expect(pagination.pages[1].url == "/browse?page=2&tag=D%26D%2B")
  }

  @Test("tag cloud links escape reserved characters")
  func tagLinkIsEscaped() {
    #expect(LeafTag(name: "D&D #1").queryValue == "D%26D%20%231")
  }
}
