import CatalogAPIClient
import Foundation
import Testing
import VaporTesting

@testable import App

@Suite("formatCount")
struct NumberFormattingTests {
  private let en = Locale(identifier: "en")

  @Test("small counts render without grouping for the en locale")
  func smallCountsNoGrouping() {
    #expect(formatCount(0, locale: en) == "0")
    #expect(formatCount(7, locale: en) == "7")
    #expect(formatCount(42, locale: en) == "42")
    #expect(formatCount(999, locale: en) == "999")
  }

  @Test("counts at and above the thousands threshold get en grouping separators")
  func enThousandsGrouping() {
    #expect(formatCount(1000, locale: en) == "1,000")
    #expect(formatCount(1234, locale: en) == "1,234")
    #expect(formatCount(12345, locale: en) == "12,345")
    #expect(formatCount(1_234_567, locale: en) == "1,234,567")
  }

  @Test("a non-en browser locale yields its own grouping separator")
  func nonEnglishGroupingSeparator() {
    #expect(formatCount(1234, locale: Locale(identifier: "de_DE")) == "1.234")
    #expect(formatCount(999, locale: Locale(identifier: "de_DE")) == "999")
  }

  // Renders the real Leaf templates (not just Swift-side label computation) to prove the
  // `countLabel` / `pendingCountLabel` fields resolore and interpolate at >1000 counts where the
  // grouping separator actually appears.

  // TypeStats ships no public memberwise init (internal by default), so decode it like the
  // controller does from the catalog-api response.
  private func typeStats(count: Int) throws -> TypeStats {
    try JSONDecoder().decode(
      TypeStats.self,
      from: Data(#"{"count": \#(count), "last_updated": null, "most_recent": null}"#.utf8))
  }

  @Test("the landing page renders a formatted count through the home template")
  func homeRendersFormattedCardCount() async throws {
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-home") { req async throws -> View in
        try await req.view.render(
          "home",
          HomeContext(
            statCards: [
              LeafTypeStatsCard(
                label: "Volumes", detailPathPrefix: "/volumes", browsePath: "/browse",
                stats: try self.typeStats(count: 1234),
                locale: Locale(identifier: "en"))
            ],
            tagCloud: [], user: nil, meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-home") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains("1,234"))
      }
    }
  }

  @Test("a detail page renders a formatted pending count through the volume template")
  func volumeDetailRendersFormattedPendingCount() async throws {
    let volume = VolumeViewModel(
      id: "1", title: "Old", description: "", notes: "",
      tags: [], systemNames: [], publisherNames: [], studioNames: [], licenseNames: [])
    let pending = (1...1234).map { testVersion(version: $0, state: "submitted") }
    let review = LeafVersionReview(
      volumeID: "1", currentVolume: volume, pending: pending, selected: pending[0],
      locale: Locale(identifier: "en"))
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-detail") { req async throws -> View in
        try await req.view.render(
          "volumes/detail",
          DetailContext(
            volume: try LeafVolumeDetail(volume, req: req), canEdit: false, canDelete: false,
            isDeleted: false,
            justProposed: false, review: review,
            conflicts: [], hasConflicts: false, user: nil, meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-detail") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains("Pending Changes (1,234)"))
      }
    }
  }
}
