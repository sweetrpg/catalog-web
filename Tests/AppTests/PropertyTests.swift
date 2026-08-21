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

}
