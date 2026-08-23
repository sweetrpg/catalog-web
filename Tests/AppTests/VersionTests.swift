import AdminAPIClient
import CatalogAPIClient
import Foundation
import Redis
import Testing
import VaporTesting

@testable import App

@Suite("Version")
struct VersionTests {
  private func testVersion(
    version: Int, state: String, submittedBy: String = "auth0|submitter",
    reviewedBy: String? = nil, reviewNote: String? = nil
  ) -> VolumeVersionAttributes {
    VolumeVersionAttributes(
      id: "ver-\(version)", recordId: "1", version: version, title: "Rusthaven",
      description: "", notes: "", format: "", coverAssetId: "", sampleAssetIds: [], state: state,
      baseVersion: version > 1 ? version - 1 : nil, submittedBy: submittedBy,
      submittedAt: Date(timeIntervalSince1970: 0), reviewedBy: reviewedBy, reviewedAt: nil,
      reviewNote: reviewNote, resultingVersion: nil)
  }

  @Test("version-history page lists every version with its state")
  func versionHistoryListsVersions() async throws {
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-versions") { req async throws -> View in
        try await req.view.render(
          "version-history",
          VersionHistoryContext(
            volumeID: "1", volumeTitle: "Rusthaven",
            versions: [
              LeafVersionSummary(testVersion(version: 2, state: "live")),
              LeafVersionSummary(testVersion(version: 1, state: "archived")),
            ],
            fetchFailed: false,
            canRollback: false, user: nil, meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-versions") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains("/volumes/1/versions/2"))
        #expect(res.body.string.contains("/volumes/1/versions/1"))
        #expect(res.body.string.contains("live"))
        #expect(res.body.string.contains("archived"))
      }
    }
  }

  @Test("version-history page hides the restore action without rollback rights")
  func versionHistoryHidesRestoreWithoutRollbackRights() async throws {
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-versions") { req async throws -> View in
        try await req.view.render(
          "version-history",
          VersionHistoryContext(
            volumeID: "1", volumeTitle: "Rusthaven",
            versions: [LeafVersionSummary(testVersion(version: 1, state: "archived"))],
            fetchFailed: false,
            canRollback: false, user: nil, meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-versions") { res in
        #expect(res.status == .ok)
        #expect(!res.body.string.contains("Restore"))
      }
    }
  }

  @Test("version-history page shows the restore action for a non-live version with rollback rights")
  func versionHistoryShowsRestoreForNonLiveVersionWithRollbackRights() async throws {
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-versions") { req async throws -> View in
        try await req.view.render(
          "version-history",
          VersionHistoryContext(
            volumeID: "1", volumeTitle: "Rusthaven",
            versions: [
              LeafVersionSummary(testVersion(version: 2, state: "live")),
              LeafVersionSummary(testVersion(version: 1, state: "archived")),
            ],
            fetchFailed: false,
            canRollback: true, user: nil, meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-versions") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains("/volumes/1/versions/1/restore"))
        #expect(!res.body.string.contains("/volumes/1/versions/2/restore"))
      }
    }
  }

  @Test("version-history page tells the user when there's genuinely no history")
  func versionHistoryShowsEmptyStateForNoVersions() async throws {
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-versions") { req async throws -> View in
        try await req.view.render(
          "version-history",
          VersionHistoryContext(
            volumeID: "1", volumeTitle: "Rusthaven",
            versions: [],
            fetchFailed: false,
            canRollback: false, user: nil, meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-versions") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains("No version history"))
        #expect(!res.body.string.contains("be loaded right now"))
      }
    }
  }

  @Test("version-history page shows an error when the fetch fails, not an empty table")
  func versionHistoryShowsErrorOnFetchFailure() async throws {
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-versions") { req async throws -> View in
        try await req.view.render(
          "version-history",
          VersionHistoryContext(
            volumeID: "1", volumeTitle: "Rusthaven",
            versions: [],
            fetchFailed: true,
            canRollback: false, user: nil, meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-versions") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains("be loaded right now"))
        #expect(!res.body.string.contains("No version history"))
      }
    }
  }

  @Test("license edit page renders correct field kinds, with long-text fields last")
  func licenseEditPageRendersFieldKindsAndOrder() async throws {
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-license-edit") { req async throws -> View in
        let user = SessionUser(
          sub: "abc", name: "Editor", email: nil, roles: ["editor"], accessToken: "test-token",
          expiry: Date().addingTimeInterval(3600))
        let base = makeEditContext(
          id: "1", basePath: "/licenses", fields: licenseFields,
          values: [
            "title": "CC BY 4.0", "status": "Accepted", "availability": "Released",
            "deed": "Full deed text", "legal_code": "Full legal text",
          ],
          user: user, meta: await PageMeta.make(req))
        return try await req.view.render(
          "licenses/edit",
          LicenseEditContext(
            base: base, tags: [], tagOptions: [], canAddTag: false, canManageVolumes: false,
            selectedVolumes: [], allVolumes: []))
      }
      try await app.testing().test(.GET, "test-license-edit") { res in
        #expect(res.status == .ok)
        let body = res.body.string
        #expect(body.contains(#"<textarea class="input" id="deed""#))
        #expect(body.contains(#"<textarea class="input" id="legal_code""#))
        #expect(body.contains(#"<select class="input" id="status""#))
        #expect(body.contains(#"<option value="Accepted"  selected >"#))
        #expect(body.contains(#"<select class="input" id="availability""#))
        #expect(body.contains(#"<option value="Released"  selected >"#))
        // deed/legal_code render after notes, not before website/status/availability.
        let notesIndex = body.range(of: #"id="notes""#)
        let deedIndex = body.range(of: #"id="deed""#)
        #expect(notesIndex != nil && deedIndex != nil)
        if let notesIndex, let deedIndex {
          #expect(notesIndex.lowerBound < deedIndex.lowerBound)
        }
      }
    }
  }

  @Test("version-detail page shows the submission and review audit trail")
  func versionDetailShowsAuditTrail() async throws {
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-version-detail") { req async throws -> View in
        try await req.view.render(
          "version-detail",
          VersionDetailContext(
            volumeID: "1",
            version: LeafVersionDetail(
              testVersion(
                version: 2, state: "rejected", reviewedBy: "auth0|editor",
                reviewNote: "not needed")),
            canRollback: false, user: nil, meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-version-detail") { res in
        #expect(res.status == .ok)
        // humanizeSubmitterID renders "auth0|x" as "auth0 #x" (no real display-name lookup yet).
        #expect(res.body.string.contains("auth0 #submitter"))
        #expect(res.body.string.contains("auth0 #editor"))
        #expect(res.body.string.contains("not needed"))
      }
    }
  }
}
