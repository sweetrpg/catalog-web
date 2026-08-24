import AdminAPIClient
import CatalogAPIClient
import Foundation
import Redis
import Testing
import VaporTesting

@testable import App

@Suite("Volumes")
struct VolumesTests {
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
        #expect(!res.body.string.contains(#"title="Edit""#))
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
        #expect(res.body.string.contains(#"title="Edit""#))
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
        #expect(res.body.string.contains("applied because the live record changed"))
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
        #expect(!res.body.string.contains("applied because the live record changed"))
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

  // Regression: localizationsDir must resolve under Resources/ (where the Dockerfile actually
  // copies the JSON files, and where they live in this checkout) - LingoVapor resolves it
  // relative to the working directory, not app.directory.resourcesDirectory, so a bare
  // "Localizations" silently 500s every browse card that calls volumeCountLabel in production
  // while still building and passing every other test. No full `configure(_:)` here (that's
  // reserved for statusPing - see the comment above adminClientDisabledByDefault): just enough
  // app setup for req.application.lingoVapor to work.
  @Test("volumeCountLabel resolves the real Localizations directory")
  func volumeCountLabelResolvesRealLocalizationsDirectory() async throws {
    try await withApp { app in
      app.lingoVapor.configuration = .init(
        defaultLocale: "en", localizationsDir: "Resources/Localizations")
      app.get("test-volume-count") { req async throws -> String in
        try await volumeCountLabel(3, req: req)
      }
      try await app.testing().test(.GET, "test-volume-count") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains("3"))
      }
    }
  }

  // Regression: CatalogController.browse kept rendering the pre-move top-level "browse" template
  // path after browse.leaf moved under volumes/ - the synthetic-route tests below never hit the
  // controller, so this shipped a 500 ("No template found for browse"). Unlike those tests this
  // exercises the real /browse route, which calls catalog-api (via URLSession - no request-level
  // stubbing point), so it needs an actual bound server standing in for catalog-api; same
  // fixed-port pattern as AppTests.withFakeAdminAPI.
  @discardableResult
  private func withFakeCatalogAPI<T>(
    port: Int,
    volumesJSON: String,
    _ test: () async throws -> T
  ) async throws -> T {
    let fake = try await Application.make(Environment(name: "testing", arguments: ["vapor"]))
    fake.http.server.configuration.hostname = "127.0.0.1"
    fake.http.server.configuration.port = port
    let emptyDoc = #"{"data":[]}"#
    fake.get("volumes") { _ in
      Response(
        status: .ok, headers: ["content-type": "application/json"],
        body: .init(string: volumesJSON))
    }
    for path in ["systems", "publishers", "studios", "licenses"] {
      fake.on(.GET, PathComponent(stringLiteral: path)) { _ in
        Response(
          status: .ok, headers: ["content-type": "application/json"],
          body: .init(string: emptyDoc))
      }
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

  @Test("browse route renders through CatalogController after the volume template move")
  func browseRouteRendersThroughController() async throws {
    let port = 18771
    try await withFakeCatalogAPI(
      port: port,
      volumesJSON: """
        {"data":[{"id":"vol-1","type":"volumes","attributes":{"title":"Rusthaven","description":"A frontier town.","tags":[{"name":"fantasy"}]}}]}
        """
    ) {
      try await withApp { app in
        app.views.use(.leaf)
        app.backendConfig = BackendConfig(
          catalogAPIURL: "http://127.0.0.1:\(port)", gameSystemsAPIURL: "unused",
          profilesAPIURL: "unused", shelfAPIURL: "unused", adminAPIURL: nil)
        try app.register(collection: CatalogController())
        try await app.testing().test(.GET, "browse") { res in
          #expect(res.status == .ok)
          #expect(res.body.string.contains("Rusthaven"))
        }
      }
    }
  }
}
