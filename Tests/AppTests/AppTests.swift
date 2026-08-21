import AdminAPIClient
import CatalogAPIClient
import Foundation
import Redis
import Testing
import VaporTesting

@testable import App

@Suite("App")
struct AppTests {


  // The landing page's own "recently catalogued" volume grid was replaced by the
  // catalog-landing-page-summary per-entity-type cards - this markup now lives only on the
  // browse page, so the coverage moved there with it.
  @Test("browse page renders a volume card's cover image with an onerror fallback")
  func browseRendersVolumeCoverWithFallback() async throws {
    let volume = VolumeViewModel(
      id: "64c7cf96a3fc8ee7407f9b76", title: "A Glorious Death", description: "", notes: "",
      tags: [], systemNames: [], publisherNames: [], studioNames: [], licenseNames: [])
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-browse") { req async throws -> View in
        try await req.view.render(
          "volumes/browse",
          BrowseContext(
            query: "", noActiveTag: true, tagCloud: [], volumes: [LeafVolumeCard(volume)],
            noResults: false,
            pagination: LeafPagination(
              currentPage: 1, totalPages: 1, hasMultiplePages: false, hasPrev: false,
              hasNext: false, prevURL: "", nextURL: "", pages: []),
            user: nil, meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-browse") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains("asset/cover/64c7cf96a3fc8ee7407f9b76"))
        #expect(
          res.body.string.contains(
            "onerror=\"this.onerror=null;this.src='http://localhost:8081"
              + "/static/img/catalog/cover-placeholder-browse.png'\""))
      }
    }
  }

  @Test("detail page shows a properties table when the volume has properties")
  func detailPageShowsPropertiesTable() async throws {
    var volume = VolumeViewModel(
      id: "1", title: "Rusthaven", description: "", notes: "",
      tags: [], systemNames: [], publisherNames: [], studioNames: [], licenseNames: [])
    volume.properties = [(name: "Page count", value: "320")]
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-detail") { req async throws -> View in
        try await req.view.render(
          "volumes/detail",
          DetailContext(
            volume: try LeafVolumeDetail(volume, req: req), canEdit: false, canDelete: false,
            isDeleted: false,
            justProposed: false, review: nil,
            conflicts: [], hasConflicts: false, user: nil, meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-detail") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains("Page count"))
        #expect(res.body.string.contains("320"))
      }
    }
  }

  @Test("detail page hides the properties table when the volume has no properties")
  func detailPageHidesPropertiesTableWithoutProperties() async throws {
    let volume = VolumeViewModel(
      id: "1", title: "Rusthaven", description: "", notes: "",
      tags: [], systemNames: [], publisherNames: [], studioNames: [], licenseNames: [])
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-detail") { req async throws -> View in
        try await req.view.render(
          "volumes/detail",
          DetailContext(
            volume: try LeafVolumeDetail(volume, req: req), canEdit: false, canDelete: false,
            isDeleted: false,
            justProposed: false, review: nil,
            conflicts: [], hasConflicts: false, user: nil, meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-detail") { res in
        #expect(res.status == .ok)
        #expect(!res.body.string.contains(">Properties<"))
      }
    }
  }

  @Test("detail page shows a sample thumbnail row and viewer when the volume has samples")
  func detailPageShowsSampleThumbnails() async throws {
    var volume = VolumeViewModel(
      id: "1", title: "Rusthaven", description: "", notes: "",
      tags: [], systemNames: [], publisherNames: [], studioNames: [], licenseNames: [])
    volume.sampleAssetIds = ["1-0", "1-1"]
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-detail") { req async throws -> View in
        try await req.view.render(
          "volumes/detail",
          DetailContext(
            volume: try LeafVolumeDetail(volume, req: req), canEdit: false, canDelete: false,
            isDeleted: false,
            justProposed: false, review: nil,
            conflicts: [], hasConflicts: false, user: nil, meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-detail") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains("asset/sample/1-0"))
        #expect(res.body.string.contains("asset/sample/1-1"))
        #expect(res.body.string.contains("sample-viewer"))
      }
    }
  }

  @Test("detail page hides the sample thumbnail row and viewer when the volume has no samples")
  func detailPageHidesSampleThumbnailsWithoutSamples() async throws {
    let volume = VolumeViewModel(
      id: "1", title: "Rusthaven", description: "", notes: "",
      tags: [], systemNames: [], publisherNames: [], studioNames: [], licenseNames: [])
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-detail") { req async throws -> View in
        try await req.view.render(
          "volumes/detail",
          DetailContext(
            volume: try LeafVolumeDetail(volume, req: req), canEdit: false, canDelete: false,
            isDeleted: false,
            justProposed: false, review: nil,
            conflicts: [], hasConflicts: false, user: nil, meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-detail") { res in
        #expect(res.status == .ok)
        #expect(!res.body.string.contains("sample-thumbnails"))
        #expect(!res.body.string.contains("sample-viewer"))
      }
    }
  }

  @Test("detail page shows only the metadata sections a volume has names for")
  func detailPageShowsOnlyPopulatedMetadataSections() async throws {
    var volume = VolumeViewModel(
      id: "1", title: "Rusthaven", description: "", notes: "",
      tags: [], systemNames: ["Shadow of the Demon Lord"],
      publisherNames: ["Schwalb Entertainment"],
      studioNames: [], licenseNames: ["OGL"])
    volume.publisherRefs = [EntityRef(id: "pub-1", name: "Schwalb Entertainment")]
    volume.licenseRefs = [EntityRef(id: "lic-1", name: "OGL")]
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-detail") { req async throws -> View in
        try await req.view.render(
          "volumes/detail",
          DetailContext(
            volume: try LeafVolumeDetail(volume, req: req), canEdit: false, canDelete: false,
            isDeleted: false,
            justProposed: false, review: nil,
            conflicts: [], hasConflicts: false, user: nil, meta: await PageMeta.make(req))
        )
      }
      try await app.testing().test(.GET, "test-detail") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains("Shadow of the Demon Lord"))
        #expect(res.body.string.contains("Schwalb Entertainment"))
        #expect(res.body.string.contains("OGL"))
        #expect(!res.body.string.contains(">Studio<"))
        #expect(!res.body.string.contains(#"title="volumes/edit""#))
      }
    }
  }

  // MARK: - catalog-volume-cover-upload

  @Test("edit page shows the cover-upload control for an editor/admin session")
  func editShowsCoverUploadControlWhenCanUploadCover() async throws {
    let volume = VolumeViewModel(
      id: "1", title: "Rusthaven", description: "", notes: "",
      tags: [], systemNames: [], publisherNames: [], studioNames: [], licenseNames: [])
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-edit") { req async throws -> View in
        try await req.view.render(
          "volumes/edit",
          EditContext(
            volume: try LeafVolumeEditForm(
              volume: volume, session: testEditSession(for: volume), userSub: "auth0-tester",
              req: req),
            canUploadCover: true, submitError: nil, user: nil,
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-edit") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains("cover-upload-input"))
      }
    }
  }

  @Test("edit page hides the cover-upload control for a submitter session")
  func editHidesCoverUploadControlWithoutRole() async throws {
    let volume = VolumeViewModel(
      id: "1", title: "Rusthaven", description: "", notes: "",
      tags: [], systemNames: [], publisherNames: [], studioNames: [], licenseNames: [])
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-edit") { req async throws -> View in
        try await req.view.render(
          "volumes/edit",
          EditContext(
            volume: try LeafVolumeEditForm(
              volume: volume, session: testEditSession(for: volume), userSub: "auth0-tester",
              req: req),
            canUploadCover: false, submitError: nil, user: nil,
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-edit") { res in
        #expect(res.status == .ok)
        #expect(!res.body.string.contains("cover-upload-input"))
      }
    }
  }

  // MARK: - volume-change-review-ui

  private func makeVersion(
    version: Int = 1, submittedBy: String = "auth0|submitter", title: String = "New"
  ) -> VolumeVersionAttributes {
    VolumeVersionAttributes(
      id: "v\(version)", recordId: "1", version: version, title: title, description: "",
      notes: "", format: "", coverAssetId: "", sampleAssetIds: [], state: "submitted",
      baseVersion: 1, submittedBy: submittedBy, submittedAt: Date(timeIntervalSince1970: 0),
      reviewedBy: nil, reviewedAt: nil, reviewNote: nil, resultingVersion: nil)
  }

  @Test("detail page shows the Edit action for a submitter/editor/admin session")
  func detailShowsEditActionWhenCanEdit() async throws {
    let volume = VolumeViewModel(
      id: "1", title: "Rusthaven", description: "", notes: "",
      tags: [], systemNames: [], publisherNames: [], studioNames: [], licenseNames: [])
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-detail") { req async throws -> View in
        try await req.view.render(
          "volumes/detail",
          DetailContext(
            volume: try LeafVolumeDetail(volume, req: req), canEdit: true, canDelete: false,
            isDeleted: false,
            justProposed: false, review: nil,
            conflicts: [], hasConflicts: false, user: nil, meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-detail") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains(#"title="volumes/edit""#))
        #expect(res.body.string.contains("/volumes/1/edit"))
      }
    }
  }

  @Test("detail page hides the review section from a submitter with no review rights")
  func detailHidesReviewSectionWithoutReviewRights() async throws {
    let volume = VolumeViewModel(
      id: "1", title: "Rusthaven", description: "", notes: "",
      tags: [], systemNames: [], publisherNames: [], studioNames: [], licenseNames: [])
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-detail") { req async throws -> View in
        try await req.view.render(
          "volumes/detail",
          DetailContext(
            // canEdit: true (submitter can propose), but review stays nil - only
            // CatalogController decides to populate it, gated on canReview, not canEdit.
            volume: try LeafVolumeDetail(volume, req: req), canEdit: true, canDelete: false,
            isDeleted: false,
            justProposed: false, review: nil,
            conflicts: [], hasConflicts: false, user: nil, meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-detail") { res in
        #expect(res.status == .ok)
        #expect(!res.body.string.contains("Pending Changes"))
      }
    }
  }

  @Test("detail page renders the description as Markdown, not raw text")
  func detailRendersDescriptionAsMarkdown() async throws {
    let volume = VolumeViewModel(
      id: "1", title: "Rusthaven", description: "**Bold** text.\n\nSecond paragraph.", notes: "",
      tags: [], systemNames: [], publisherNames: [], studioNames: [], licenseNames: [])
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-detail") { req async throws -> View in
        try await req.view.render(
          "volumes/detail",
          DetailContext(
            volume: try LeafVolumeDetail(volume, req: req), canEdit: false, canDelete: false,
            isDeleted: false,
            justProposed: false, review: nil,
            conflicts: [], hasConflicts: false, user: nil, meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-detail") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains("<strong>Bold</strong>"))
        #expect(res.body.string.contains("Second paragraph."))
        #expect(!res.body.string.contains("**Bold**"))
      }
    }
  }

  @Test("detail page shows a pending-change indicator and diff for an editor")
  func detailShowsPendingChangeReviewForEditor() async throws {
    let volume = VolumeViewModel(
      id: "1", title: "Old", description: "", notes: "",
      tags: [], systemNames: [], publisherNames: [], studioNames: [], licenseNames: [])
    let version = makeVersion()
    let review = LeafVersionReview(
      volumeID: "1", currentVolume: volume, pending: [version], selected: version)
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
        #expect(res.body.string.contains("Pending Changes (1)"))
        #expect(res.body.string.contains("Old"))
        #expect(res.body.string.contains("New"))
        #expect(res.body.string.contains("Accept All"))
        #expect(res.body.string.contains("Accept Selected"))
        #expect(res.body.string.contains("Reject"))
        // Single pending proposal: no picker <select>, just the plain submitted-by line.
        #expect(!res.body.string.contains("<select"))
      }
    }
  }

  @Test("detail page shows a proposal picker when more than one proposal is pending")
  func detailShowsProposalPickerForMultiplePending() async throws {
    let volume = VolumeViewModel(
      id: "1", title: "Rusthaven", description: "", notes: "",
      tags: [], systemNames: [], publisherNames: [], studioNames: [], licenseNames: [])
    let first = makeVersion(version: 1, submittedBy: "auth0|alice")
    let second = makeVersion(version: 2, submittedBy: "auth0|bob")
    let review = LeafVersionReview(
      volumeID: "1", currentVolume: volume, pending: [first, second], selected: first)
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
        #expect(res.body.string.contains("Pending Changes (2)"))
        #expect(res.body.string.contains("<select"))
        #expect(res.body.string.contains("auth0|alice"))
        #expect(res.body.string.contains("auth0|bob"))
      }
    }
  }

  @Test("detail page surfaces conflicting fields after a partial accept")
  func detailShowsConflictBanner() async throws {
    let volume = VolumeViewModel(
      id: "1", title: "Rusthaven", description: "", notes: "",
      tags: [], systemNames: [], publisherNames: [], studioNames: [], licenseNames: [])
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-detail") { req async throws -> View in
        try await req.view.render(
          "volumes/detail",
          DetailContext(
            volume: try LeafVolumeDetail(volume, req: req), canEdit: false, canDelete: false,
            isDeleted: false,
            justProposed: false, review: nil,
            conflicts: ["title"], hasConflicts: true, user: nil, meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-detail") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains("weren't applied"))
        #expect(res.body.string.contains("title"))
      }
    }
  }

  @Test("detail page hides the conflict banner when there are no conflicts")
  func detailHidesConflictBannerWhenEmpty() async throws {
    let volume = VolumeViewModel(
      id: "1", title: "Rusthaven", description: "", notes: "",
      tags: [], systemNames: [], publisherNames: [], studioNames: [], licenseNames: [])
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-detail") { req async throws -> View in
        try await req.view.render(
          "volumes/detail",
          DetailContext(
            volume: try LeafVolumeDetail(volume, req: req), canEdit: false, canDelete: false,
            isDeleted: false,
            justProposed: false, review: nil,
            conflicts: [], hasConflicts: false, user: nil, meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-detail") { res in
        #expect(res.status == .ok)
        #expect(!res.body.string.contains("weren't applied"))
      }
    }
  }

  @Test("edit form pre-fills the volume's current title/description/notes")
  func editFormPrefillsFields() async throws {
    let volume = VolumeViewModel(
      id: "1", title: "Rusthaven", description: "A dark fantasy setting.", notes: "Draft notes",
      tags: [], systemNames: [], publisherNames: [], studioNames: [], licenseNames: [])
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-edit") { req async throws -> View in
        try await req.view.render(
          "volumes/edit",
          EditContext(
            volume: try LeafVolumeEditForm(
              volume: volume, session: testEditSession(for: volume), userSub: "auth0-tester",
              req: req),
            canUploadCover: false, submitError: nil, user: nil,
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-edit") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains(#"value="Rusthaven""#))
        #expect(res.body.string.contains("A dark fantasy setting."))
        #expect(res.body.string.contains("Draft notes"))
        #expect(res.body.string.contains(#"action="/volumes/1/edit""#))
      }
    }
  }

  @Test("edit form renders inline edit affordances for title and description")
  func editFormRendersInlineEditControls() async throws {
    let volume = VolumeViewModel(
      id: "1", title: "Rusthaven", description: "A dark fantasy setting.", notes: "",
      tags: [], systemNames: [], publisherNames: [], studioNames: [], licenseNames: [])
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-edit") { req async throws -> View in
        try await req.view.render(
          "volumes/edit",
          EditContext(
            volume: try LeafVolumeEditForm(
              volume: volume, session: testEditSession(for: volume), userSub: "auth0-tester",
              req: req),
            canUploadCover: false, submitError: nil, user: nil,
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-edit") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains("icons/edit.svg"))
        #expect(res.body.string.contains("icons/accept.svg"))
        #expect(res.body.string.contains("icons/cancel.svg"))
        #expect(res.body.string.contains(#"data-field="title" data-field-type="line""#))
        #expect(res.body.string.contains(#"data-field="description" data-field-type="block""#))
        #expect(res.body.string.contains(#"data-field="notes" data-field-type="block""#))
      }
    }
  }

  // MARK: - MaintenanceModeMiddleware

  /// `AdminAPIClient.AdminClient` makes real `URLSession` calls - there's no request-level
  /// stubbing point - so exercising "admin-api reports an active maintenance-mode record"
  /// needs an actual bound HTTP server standing in for admin-api, not a mock. A fixed port
  /// keeps this simple; these tests run serially against it (Swift Testing still runs
  /// `@Suite` tests in one struct concurrently by default, but nothing else in this file binds
  /// this port).
  @discardableResult
  private func withFakeAdminAPI<T>(
    port: Int,
    maintenanceModesJSON: String,
    _ test: () async throws -> T
  ) async throws -> T {
    // Not `.testing` - that preset sanitizes `ProcessInfo.processInfo.arguments`, which under
    // `swift test` includes flags like `--test-bundle-path` that Vapor's own sanitizer doesn't
    // recognize and `startup()`'s command parser then rejects. A real bound listener (unlike
    // the app-under-test, which never calls `startup()` and instead uses `.testing()`'s
    // in-memory transport) needs `startup()` to actually run the serve command, so the
    // environment's arguments must be the app's own, not the test runner's.
    let fake = try await Application.make(Environment(name: "testing", arguments: ["vapor"]))
    fake.http.server.configuration.hostname = "127.0.0.1"
    fake.http.server.configuration.port = port
    fake.get("maintenance-modes", "active") { _ -> Response in
      Response(
        status: .ok, headers: ["content-type": "application/json"],
        body: .init(string: maintenanceModesJSON))
    }
    do {
      try await fake.startup()
    } catch {
      try? await fake.asyncShutdown()
      throw error
    }

    let result: T
    do {
      result = try await test()
    } catch {
      try? await fake.asyncShutdown()
      throw error
    }
    try await fake.asyncShutdown()
    return result
  }

  // MARK: - durable-volume-editing

  // The three tests below deliberately avoid a live Redis connection - this repo's CI (the
  // shared `swift-ci.yaml` reusable workflow) has no Redis service container, and every
  // existing Redis-touching test in this file (`currentUser...`) already works around that by
  // testing only the disabled/unreachable path rather than a real round trip. `EditSession`'s
  // wire format is exercised here as a pure `Codable` round trip instead - the part that
  // actually needed verifying (the `iso8601` date strategy producing something Go's
  // `time.Time` can parse, not the Redis transport itself, which `EditSessionAccess.swift`'s
  // own use of the standard `RedisClient` API doesn't need app-level re-testing).

  @Test("EditSession round-trips through JSON with ISO8601 dates")
  func editSessionJSONRoundTrips() throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let original = EditSession(
      recordId: "vol-1",
      fields: ["title": .string("Staged Title"), "description": .string("Staged description")],
      stagedCoverAssetId: "cover-abc", sampleAssetIds: ["s1", "s2"],
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      updatedAt: Date(timeIntervalSince1970: 1_700_000_100))

    let data = try encoder.encode(original)
    let decoded = try decoder.decode(EditSession.self, from: data)

    #expect(decoded.recordId == original.recordId)
    #expect(decoded.fields == original.fields)
    #expect(decoded.stagedCoverAssetId == original.stagedCoverAssetId)
    #expect(decoded.sampleAssetIds == original.sampleAssetIds)
    #expect(decoded.createdAt == original.createdAt)
  }

  @Test("EditSession JSON encodes dates as RFC3339 strings, not epoch numbers")
  func editSessionJSONEncodesRFC3339Dates() throws {
    // catalog-api's `editsession.Session` decodes `createdAt`/`updatedAt` into Go's
    // `time.Time`, which expects an RFC3339 string - the default `JSONEncoder` (no explicit
    // `dateEncodingStrategy`) would instead emit a bare epoch-seconds number, which Go's
    // `time.Time` JSON unmarshaling rejects outright. This confirms the actual wire shape
    // `EditSessionAccess.swift` produces, not just that some string round-trips.
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let session = EditSession(
      recordId: "vol-1", fields: [:], stagedCoverAssetId: nil, sampleAssetIds: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      updatedAt: Date(timeIntervalSince1970: 1_700_000_000))

    let data = try encoder.encode(session)
    let json = try #require(String(data: data, encoding: .utf8))

    #expect(json.contains("2023-11-14T22:13:20Z"))
  }

  @Test("edit-session Redis key is namespaced by both user and record type")
  func editSessionKeyFormat() {
    // Mirrors catalog-api's editsession.Key exactly - the two sides must agree on this format
    // or neither can ever see the other's writes/reads.
    func key(userID: String, recordType: String) -> String {
      "edit-session:\(userID):\(recordType)"
    }
    #expect(key(userID: "user-1", recordType: "volume") == "edit-session:user-1:volume")
    #expect(
      key(userID: "user-1", recordType: "volume") != key(userID: "user-1", recordType: "publisher")
    )
    #expect(
      key(userID: "user-1", recordType: "volume") != key(userID: "user-2", recordType: "volume"))
  }

  @Test("edit page shows the session's staged field values, not the volume's live ones")
  func editPageShowsSessionValuesOverLiveValues() async throws {
    let volume = VolumeViewModel(
      id: "1", title: "Live Title", description: "Live description", notes: "",
      tags: [], systemNames: [], publisherNames: [], studioNames: [], licenseNames: [])
    let session = EditSession(
      recordId: "1",
      fields: ["title": .string("Session Title"), "description": .string("Live description")],
      stagedCoverAssetId: nil, sampleAssetIds: nil, createdAt: Date(), updatedAt: Date())
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-edit") { req async throws -> View in
        try await req.view.render(
          "volumes/edit",
          EditContext(
            volume: try LeafVolumeEditForm(
              volume: volume, session: session, userSub: "auth0-tester", req: req),
            canUploadCover: false, submitError: nil, user: nil,
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-edit") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains(#"value="Session Title""#))
        #expect(!res.body.string.contains(#"value="Live Title""#))
      }
    }
  }

  @Test("edit page publisher/studio pickers show existing options and no create-new affordance")
  func editPagePublisherStudioPickersRenderOptionsAndNoCreatePath() async throws {
    let volume = VolumeViewModel(
      id: "1", title: "Rusthaven", description: "", notes: "",
      tags: [], systemNames: [], publisherNames: ["Existing Co"], publisherIds: ["pub-1"],
      studioNames: [], licenseNames: [])
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-edit") { req async throws -> View in
        try await req.view.render(
          "volumes/edit",
          EditContext(
            volume: try LeafVolumeEditForm(
              volume: volume, session: testEditSession(for: volume), userSub: "auth0-tester",
              req: req,
              publisherOptions: [("pub-1", "Existing Co"), ("pub-2", "Other Publisher")],
              studioOptions: [("studio-1", "Some Studio")]),
            canUploadCover: false, submitError: nil, user: nil,
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-edit") { res in
        #expect(res.status == .ok)
        // The full candidate list is embedded for client-side filtering...
        #expect(res.body.string.contains("Other Publisher"))
        #expect(res.body.string.contains("Some Studio"))
        // ...but there's no way to submit a name that isn't one of those existing options -
        // the picker's filter input has no associated create/submit action of its own, only
        // the JS-driven autosave to /edit/session/associations.
        #expect(!res.body.string.contains("Create publisher"))
        #expect(!res.body.string.contains("Create studio"))
        #expect(!res.body.string.contains("Add new publisher"))
        #expect(!res.body.string.contains("Add new studio"))
      }
    }
  }

  @Test("edit page shows a selected publisher chip for an already-linked publisher")
  func editPageShowsSelectedPublisherChip() async throws {
    let volume = VolumeViewModel(
      id: "1", title: "Rusthaven", description: "", notes: "",
      tags: [], systemNames: [], publisherNames: ["Existing Co"], publisherIds: ["pub-1"],
      studioNames: [], licenseNames: [])
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-edit") { req async throws -> View in
        try await req.view.render(
          "volumes/edit",
          EditContext(
            volume: try LeafVolumeEditForm(
              volume: volume, session: testEditSession(for: volume), userSub: "auth0-tester",
              req: req,
              publisherOptions: [("pub-1", "Existing Co")], studioOptions: []),
            canUploadCover: false, submitError: nil, user: nil,
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-edit") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains(#"data-id="pub-1""#))
        #expect(res.body.string.contains("Existing Co"))
      }
    }
  }

  @Test("edit page prefers a session's pending publisher selection over the volume's live ones")
  func editPageShowsSessionPublisherSelectionOverLiveOnes() async throws {
    let volume = VolumeViewModel(
      id: "1", title: "Rusthaven", description: "", notes: "",
      tags: [], systemNames: [], publisherNames: ["Live Publisher"], publisherIds: ["pub-1"],
      studioNames: [], licenseNames: [])
    var session = testEditSession(for: volume)
    session.fields["publisherIds"] = .stringArray(["pub-2"])
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-edit") { req async throws -> View in
        try await req.view.render(
          "volumes/edit",
          EditContext(
            volume: try LeafVolumeEditForm(
              volume: volume, session: session, userSub: "auth0-tester", req: req,
              publisherOptions: [("pub-1", "Live Publisher"), ("pub-2", "Session Publisher")],
              studioOptions: []),
            canUploadCover: false, submitError: nil, user: nil,
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-edit") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains(#"data-id="pub-2""#))
        #expect(res.body.string.contains("Session Publisher"))
        #expect(!res.body.string.contains(#"data-id="pub-1""#))
      }
    }
  }

  @Test("edit page shows an inline error banner after a failed finalize")
  func editPageShowsSubmitError() async throws {
    let volume = VolumeViewModel(
      id: "1", title: "Rusthaven", description: "", notes: "",
      tags: [], systemNames: [], publisherNames: [], studioNames: [], licenseNames: [])
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-edit") { req async throws -> View in
        try await req.view.render(
          "volumes/edit",
          EditContext(
            volume: try LeafVolumeEditForm(
              volume: volume, session: testEditSession(for: volume), userSub: "auth0-tester",
              req: req),
            canUploadCover: false,
            submitError: "You have 25 pending submissions, at your cap of 25.", user: nil,
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-edit") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains("You have 25 pending submissions"))
      }
    }
  }

  @Test("edit-session-conflict page names both volumes and links to continue editing the other one")
  func editSessionConflictPageRenders() async throws {
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-conflict") { req async throws -> View in
        try await req.view.render(
          "edit-session-conflict",
          EditSessionConflictContext(
            volumeID: "2", volumeTitle: "New Volume", otherVolumeID: "1",
            otherVolumeTitle: "In-Progress Volume", otherStagedCoverPath: "", user: nil,
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-conflict") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains("In-Progress Volume"))
        #expect(res.body.string.contains(#"href="/volumes/1/edit""#))
        #expect(res.body.string.contains("New Volume"))
      }
    }
  }

  @Test("edit-session-conflict page omits the staged-cover reclaim script when there is none")
  func editSessionConflictPageOmitsReclaimScriptWithoutStagedCover() async throws {
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-conflict") { req async throws -> View in
        try await req.view.render(
          "edit-session-conflict",
          EditSessionConflictContext(
            volumeID: "2", volumeTitle: "New Volume", otherVolumeID: "1",
            otherVolumeTitle: "In-Progress Volume", otherStagedCoverPath: "", user: nil,
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-conflict") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains("discard-other-form"))
        #expect(!res.body.string.contains("keepalive: true"))
      }
    }
  }

  // MARK: - durable-volume-editing task 8 (contributor linking)

  @Test("edit page contributor dialog completes a credit from person + contribution type options")
  func editPageContributorDialogRendersPersonAndTypeOptions() async throws {
    let volume = VolumeViewModel(
      id: "1", title: "Rusthaven", description: "", notes: "",
      tags: [], systemNames: [], publisherNames: [], studioNames: [], licenseNames: [])
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-edit") { req async throws -> View in
        try await req.view.render(
          "volumes/edit",
          EditContext(
            volume: try LeafVolumeEditForm(
              volume: volume, session: testEditSession(for: volume), userSub: "auth0-tester",
              req: req,
              personOptions: [("person-1", "Gary Gygax")],
              contributionTypeOptions: ["Author", "Illustrator"], canAddContributionType: true),
            canUploadCover: false, submitError: nil, user: nil,
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-edit") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains("add-contributor-trigger"))
        #expect(res.body.string.contains("Gary Gygax"))
        #expect(res.body.string.contains("Author"))
        #expect(res.body.string.contains("Illustrator"))
        #expect(res.body.string.contains("/volumes/1/edit/session/credits"))
      }
    }
  }

  @Test("edit page shows the add-new-contribution-type affordance for an editor/admin session")
  func editPageShowsAddContributionTypeForEditor() async throws {
    let volume = VolumeViewModel(
      id: "1", title: "Rusthaven", description: "", notes: "",
      tags: [], systemNames: [], publisherNames: [], studioNames: [], licenseNames: [])
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-edit") { req async throws -> View in
        try await req.view.render(
          "volumes/edit",
          EditContext(
            volume: try LeafVolumeEditForm(
              volume: volume, session: testEditSession(for: volume), userSub: "auth0-tester",
              req: req,
              contributionTypeOptions: ["Author"], canAddContributionType: true),
            canUploadCover: false, submitError: nil, user: nil,
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-edit") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains("contributor-new-type"))
        #expect(res.body.string.contains("Add type"))
        #expect(res.body.string.contains("/volumes/1/edit/vocabulary/contribution-type"))
      }
    }
  }

  @Test("edit page hides the add-new-contribution-type affordance for a submitter session")
  func editPageHidesAddContributionTypeForSubmitter() async throws {
    let volume = VolumeViewModel(
      id: "1", title: "Rusthaven", description: "", notes: "",
      tags: [], systemNames: [], publisherNames: [], studioNames: [], licenseNames: [])
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-edit") { req async throws -> View in
        try await req.view.render(
          "volumes/edit",
          EditContext(
            volume: try LeafVolumeEditForm(
              volume: volume, session: testEditSession(for: volume), userSub: "auth0-tester",
              req: req,
              contributionTypeOptions: ["Author"], canAddContributionType: false),
            canUploadCover: false, submitError: nil, user: nil,
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-edit") { res in
        #expect(res.status == .ok)
        // The JS still references `contributor-new-type` by id (harmlessly - `getElementById`
        // returns nil and every use is guarded), so this checks for the actual markup element,
        // not the bare id string which also appears in the always-present script block.
        #expect(!res.body.string.contains(#"id="contributor-new-type""#))
        #expect(!res.body.string.contains(">Add type<"))
      }
    }
  }

  @Test("edit page falls back to a volume's live credits when the session has none staged")
  func editPageShowsLiveCreditsWithoutSessionOverride() async throws {
    var volume = VolumeViewModel(
      id: "1", title: "Rusthaven", description: "", notes: "",
      tags: [], systemNames: [], publisherNames: [], studioNames: [], licenseNames: [])
    volume.credits = [(personId: "person-1", role: "Author", person: "Gary Gygax")]
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-edit") { req async throws -> View in
        try await req.view.render(
          "volumes/edit",
          EditContext(
            volume: try LeafVolumeEditForm(
              volume: volume, session: testEditSession(for: volume), userSub: "auth0-tester",
              req: req),
            canUploadCover: false, submitError: nil, user: nil,
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-edit") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains(#"data-person-id="person-1""#))
        #expect(res.body.string.contains("Gary Gygax"))
        #expect(res.body.string.contains("Author"))
      }
    }
  }

  @Test("edit page contributor dialog has no path to create a new person")
  func editPageContributorDialogHasNoCreatePersonPath() async throws {
    let volume = VolumeViewModel(
      id: "1", title: "Rusthaven", description: "", notes: "",
      tags: [], systemNames: [], publisherNames: [], studioNames: [], licenseNames: [])
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-edit") { req async throws -> View in
        try await req.view.render(
          "volumes/edit",
          EditContext(
            volume: try LeafVolumeEditForm(
              volume: volume, session: testEditSession(for: volume), userSub: "auth0-tester",
              req: req,
              personOptions: [("person-1", "Gary Gygax")], canAddContributionType: true),
            canUploadCover: false, submitError: nil, user: nil,
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-edit") { res in
        #expect(res.status == .ok)
        #expect(!res.body.string.contains("Create person"))
        #expect(!res.body.string.contains("Add new person"))
        #expect(!res.body.string.contains("Add person"))
      }
    }
  }

  // MARK: - durable-volume-editing task 9 (properties table)

  @Test("edit page shows a selected property chip and the name/value picker")
  func editPageShowsPropertyPicker() async throws {
    var volume = VolumeViewModel(
      id: "1", title: "Rusthaven", description: "", notes: "",
      tags: [], systemNames: [], publisherNames: [], studioNames: [], licenseNames: [])
    volume.properties = [(name: "Page count", value: "320")]
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-edit") { req async throws -> View in
        try await req.view.render(
          "volumes/edit",
          EditContext(
            volume: try LeafVolumeEditForm(
              volume: volume, session: testEditSession(for: volume), userSub: "auth0-tester",
              req: req,
              propertyNameOptions: ["Page count", "Weight"], canAddPropertyName: true),
            canUploadCover: false, submitError: nil, user: nil,
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-edit") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains(#"data-name="Page count""#))
        #expect(res.body.string.contains("320"))
        #expect(res.body.string.contains("Weight"))
        #expect(res.body.string.contains("/volumes/1/edit/session/properties"))
      }
    }
  }

  @Test("edit page shows the add-new-property-name affordance for an editor/admin session")
  func editPageShowsAddPropertyNameForEditor() async throws {
    let volume = VolumeViewModel(
      id: "1", title: "Rusthaven", description: "", notes: "",
      tags: [], systemNames: [], publisherNames: [], studioNames: [], licenseNames: [])
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-edit") { req async throws -> View in
        try await req.view.render(
          "volumes/edit",
          EditContext(
            volume: try LeafVolumeEditForm(
              volume: volume, session: testEditSession(for: volume), userSub: "auth0-tester",
              req: req,
              propertyNameOptions: ["Page count"], canAddPropertyName: true),
            canUploadCover: false, submitError: nil, user: nil,
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-edit") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains("property-new-name"))
        #expect(res.body.string.contains("/volumes/1/edit/vocabulary/property-name"))
      }
    }
  }

  @Test("edit page hides the add-new-property-name affordance for a submitter session")
  func editPageHidesAddPropertyNameForSubmitter() async throws {
    let volume = VolumeViewModel(
      id: "1", title: "Rusthaven", description: "", notes: "",
      tags: [], systemNames: [], publisherNames: [], studioNames: [], licenseNames: [])
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-edit") { req async throws -> View in
        try await req.view.render(
          "volumes/edit",
          EditContext(
            volume: try LeafVolumeEditForm(
              volume: volume, session: testEditSession(for: volume), userSub: "auth0-tester",
              req: req,
              propertyNameOptions: ["Page count"], canAddPropertyName: false),
            canUploadCover: false, submitError: nil, user: nil,
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-edit") { res in
        #expect(res.status == .ok)
        // The JS still references `property-new-name` by id (harmlessly - `getElementById`
        // returns nil and every use is guarded), so this checks for the actual markup element,
        // not the bare id string which also appears in the always-present script block.
        #expect(!res.body.string.contains(#"id="property-new-name""#))
        #expect(!res.body.string.contains(">Add name<"))
      }
    }
  }

  @Test("edit page falls back to a volume's live properties when the session has none staged")
  func editPageShowsLivePropertiesWithoutSessionOverride() async throws {
    var volume = VolumeViewModel(
      id: "1", title: "Rusthaven", description: "", notes: "",
      tags: [], systemNames: [], publisherNames: [], studioNames: [], licenseNames: [])
    volume.properties = [(name: "Page count", value: "320")]
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-edit") { req async throws -> View in
        try await req.view.render(
          "volumes/edit",
          EditContext(
            volume: try LeafVolumeEditForm(
              volume: volume, session: testEditSession(for: volume), userSub: "auth0-tester",
              req: req),
            canUploadCover: false, submitError: nil, user: nil,
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-edit") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains(#"data-name="Page count""#))
        #expect(res.body.string.contains("320"))
      }
    }
  }

  @Test("edit page prefers a session's pending property selection over the volume's live ones")
  func editPageShowsSessionPropertySelectionOverLiveOnes() async throws {
    var volume = VolumeViewModel(
      id: "1", title: "Rusthaven", description: "", notes: "",
      tags: [], systemNames: [], publisherNames: [], studioNames: [], licenseNames: [])
    volume.properties = [(name: "Page count", value: "320")]
    var session = testEditSession(for: volume)
    session.fields["properties"] = .objectArray([["name": "Weight", "value": "1.2kg"]])
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-edit") { req async throws -> View in
        try await req.view.render(
          "volumes/edit",
          EditContext(
            volume: try LeafVolumeEditForm(
              volume: volume, session: session, userSub: "auth0-tester", req: req),
            canUploadCover: false, submitError: nil, user: nil,
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-edit") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains(#"data-name="Weight""#))
        #expect(res.body.string.contains("1.2kg"))
        #expect(!res.body.string.contains(#"data-name="Page count""#))
      }
    }
  }

  // MARK: - durable-volume-editing task 11 (sample pages)

  @Test("edit page shows the volume's live samples read-only alongside the upload control")
  func editPageShowsLiveSamplesReadOnly() async throws {
    var volume = VolumeViewModel(
      id: "1", title: "Rusthaven", description: "", notes: "",
      tags: [], systemNames: [], publisherNames: [], studioNames: [], licenseNames: [])
    volume.sampleAssetIds = ["1-0"]
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-edit") { req async throws -> View in
        try await req.view.render(
          "volumes/edit",
          EditContext(
            volume: try LeafVolumeEditForm(
              volume: volume, session: testEditSession(for: volume), userSub: "auth0-tester",
              req: req),
            canUploadCover: false, submitError: nil, user: nil,
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-edit") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains("asset/sample/1-0"))
        #expect(res.body.string.contains("sample-thumbnail-small"))
        #expect(res.body.string.contains("sample-upload-input"))
        #expect(res.body.string.contains(#"accept="image/png,image/jpeg,image/webp""#))
      }
    }
  }

  @Test("edit page shows staged sample chips from the session, up to the 5-sample cap")
  func editPageShowsStagedSampleChipsAtCap() async throws {
    let volume = VolumeViewModel(
      id: "1", title: "Rusthaven", description: "", notes: "",
      tags: [], systemNames: [], publisherNames: [], studioNames: [], licenseNames: [])
    var session = testEditSession(for: volume)
    session.sampleAssetIds = [
      "auth0-tester-0", "auth0-tester-1", "auth0-tester-2", "auth0-tester-3", "auth0-tester-4",
    ]
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-edit") { req async throws -> View in
        try await req.view.render(
          "volumes/edit",
          EditContext(
            volume: try LeafVolumeEditForm(
              volume: volume, session: session, userSub: "auth0-tester", req: req),
            canUploadCover: false, submitError: nil, user: nil,
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-edit") { res in
        #expect(res.status == .ok)
        for n in 0..<5 {
          #expect(res.body.string.contains(#"data-id="auth0-tester-\#(n)""#))
        }
        // The client-side cap is enforced by JS reading this constant, not by omitting markup -
        // this asserts the cap value actually reaches the page's script.
        #expect(res.body.string.contains("MAX_SAMPLES = 5"))
      }
    }
  }

  @Test(
    "edit page shows no sample section content when the volume has neither live nor staged samples")
  func editPageHidesSamplesWhenNoneExist() async throws {
    let volume = VolumeViewModel(
      id: "1", title: "Rusthaven", description: "", notes: "",
      tags: [], systemNames: [], publisherNames: [], studioNames: [], licenseNames: [])
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-edit") { req async throws -> View in
        try await req.view.render(
          "volumes/edit",
          EditContext(
            volume: try LeafVolumeEditForm(
              volume: volume, session: testEditSession(for: volume), userSub: "auth0-tester",
              req: req),
            canUploadCover: false, submitError: nil, user: nil,
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-edit") { res in
        #expect(res.status == .ok)
        #expect(!res.body.string.contains("replaces this whole set"))
        #expect(!res.body.string.contains("sample-thumbnail\""))
      }
    }
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
        #expect(!res.body.string.contains("couldn't be loaded"))
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
        #expect(res.body.string.contains("couldn't be loaded"))
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
}
