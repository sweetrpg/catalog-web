import AdminAPIClient
import CatalogAPIClient
import Foundation
import Redis
import Testing
import VaporTesting

@testable import App

@Suite("Property")
struct PropertyTests {
  @Test("normalizePropertyKey lowercases and collapses spaces to single dashes")
  func normalizePropertyKeyLowercasesAndDashes() {
    #expect(normalizePropertyKey("Page Count") == "page-count")
    #expect(normalizePropertyKey("  ISBN 13  ") == "isbn-13")
    #expect(normalizePropertyKey("format") == "format")
    #expect(normalizePropertyKey("Multiple   Spaces") == "multiple-spaces")
  }

  @Test("propertyDisplayLabel humanizes a key with no localization entry")
  func propertyDisplayLabelHumanizesUnknownKey() async throws {
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-label") { req async throws -> String in
        try propertyDisplayLabel("page-count", req: req)
      }
      try await app.testing().test(.GET, "test-label") { res in
        #expect(res.status == .ok)
        #expect(res.body.string == "Page Count")
      }
    }
  }

  @Test("propertyDisplayLabel prefers a localization over humanizing")
  func propertyDisplayLabelPrefersLocalization() async throws {
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-label") { req async throws -> String in
        try propertyDisplayLabel("format", req: req)
      }
      try await app.testing().test(.GET, "test-label") { res in
        #expect(res.status == .ok)
        // Resources/Localizations/en.json defines catalog.property.format.
        #expect(res.body.string == "Format")
      }
    }
  }

  @Test("autosaved property entries keep kind, defaulting to string")
  func autosavedPropertyKeepsKind() throws {
    let json = #"[{"name":"pages","value":"32","kind":"int"},{"name":"isbn","value":"1"}]"#
    let input = try JSONDecoder().decode(
      [VolumesController.AutosaveProperty].self, from: Data(json.utf8))
    #expect(input.map { $0.sessionEntry["kind"] } == ["int", "string"])
  }

  @Test("edit page chips carry each property's kind", arguments: [false, true])
  func editPageChipsCarryKind(fromSession: Bool) async throws {
    var volume = VolumeViewModel(
      id: "1", title: "T", description: "", notes: "",
      tags: [], systemNames: [], publisherNames: [], studioNames: [], licenseNames: [])
    volume.properties = [("pages", "32", "int")]
    var session = EditSession(
      recordId: "1", fields: [:], stagedCoverAssetId: nil, sampleAssetIds: nil,
      createdAt: Date(), updatedAt: Date())
    if fromSession {
      session.fields["properties"] = .objectArray([["name": "pages", "value": "32", "kind": "int"]])
    }
    let staged = session
    let live = volume
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-edit") { req async throws -> View in
        try await req.view.render(
          "volumes/edit",
          EditContext(
            volume: try LeafVolumeEditForm(
              volume: live, session: staged, userSub: "u1", req: req),
            canUploadCover: false, submitError: nil, user: nil,
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-edit") { res in
        #expect(res.body.string.contains(#"data-kind="int""#))
        #expect(res.body.string.contains("kind: chip.dataset.kind"))
      }
    }
  }
}
