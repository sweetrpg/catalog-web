import AdminAPIClient
import CatalogAPIClient
import Foundation
import Redis
import Testing
import VaporTesting

@testable import App

@Suite("App")
struct AppTests {
  @Test("status ping responds ok and reports the build version")
  func statusPing() async throws {
    try await withApp(configure: configure) { app in
      try await app.testing().test(.GET, "status/ping") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains(#""version":"dev""#))
      }
    }
  }

  // These two exercise AdminClient directly against a minimal app (no full `configure(_:)` -
  // that bootstraps the global Swift Metrics backend, which can only happen once per process,
  // and Swift Testing runs tests concurrently by default) - just enough app setup for
  // `req.adminClient` to work: a route and, where needed, an overridden `backendConfig`.

  @Test("AdminClient returns no banners when ADMIN_API_URL is unset")
  func adminClientDisabledByDefault() async throws {
    try await withApp { app in
      app.get("test-banners") { req async -> [LeafBanner] in
        await req.adminClient.fetchBanners(scopes: ["platform"]).map(LeafBanner.init)
      }
      try await app.testing().test(.GET, "test-banners") { res in
        #expect(res.status == .ok)
        let banners = try res.content.decode([LeafBanner].self)
        #expect(banners.isEmpty)
      }
    }
  }

  @Test("AdminClient fails open when admin-api is unreachable")
  func adminClientFailsOpenOnUnreachableHost() async throws {
    try await withApp { app in
      app.backendConfig = BackendConfig(
        catalogAPIURL: "unused", gameSystemsAPIURL: "unused", profilesAPIURL: "unused",
        shelfAPIURL: "unused", adminAPIURL: "http://127.0.0.1:1")
      app.get("test-banners") { req async -> [LeafBanner] in
        await req.adminClient.fetchBanners(scopes: ["platform"]).map(LeafBanner.init)
      }
      try await app.testing().test(.GET, "test-banners") { res in
        #expect(res.status == .ok)
        let banners = try res.content.decode([LeafBanner].self)
        #expect(banners.isEmpty)
      }
    }
  }

  // Mirrors the two above: no full `configure(_:)`, just enough for `req.currentUser` to work.

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

  // Renders a real Leaf template (not just a Swift-side compile check, since Leaf resolves
  // `#(meta.loginURL)` dynamically at render time) to confirm the header partial's login/logout
  // links interpolate correctly.

  @Test("header renders the log-in link when logged out")
  func headerRendersLogInLink() async throws {
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-home") { req async throws -> View in
        try await req.view.render(
          "home",
          HomeContext(
            volumeCount: 0, trending: [], tagCloud: [], user: nil,
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-home") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains(#"href="/auth/login?return_to=/test-home""#))
        #expect(!res.body.string.contains("Log Out"))
        // The avatar menu is always present (mystery-man icon + a Log in item), not hidden
        // when logged out - see feat/avatar-menu-always-present-and-theme.
        #expect(res.body.string.contains("avatar-menu-trigger"))
        #expect(res.body.string.contains("mystery-man.svg"))
      }
    }
  }

  @Test("header renders the avatar menu without Admin for a non-admin session")
  func headerRendersAvatarMenuWithoutAdminForNonAdmin() async throws {
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-home") { req async throws -> View in
        try await req.view.render(
          "home",
          HomeContext(
            volumeCount: 0, trending: [], tagCloud: [],
            user: LeafUser(
              SessionUser(
                sub: "abc", name: "Alice", email: nil, roles: [], accessToken: "test-token",
                expiry: Date().addingTimeInterval(3600))),
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-home") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains("avatar-menu-trigger"))
        #expect(res.body.string.contains(#"href="/users""#))
        #expect(!res.body.string.contains(#"href="/admin""#))
        #expect(res.body.string.contains("avatar-menu-item-danger"))
        #expect(res.body.string.contains(#"action="/auth/logout?return_to=/test-home""#))
      }
    }
  }

  @Test("header renders a Gravatar image with an onerror fallback when the session has an email")
  func headerRendersGravatarImageWhenEmailPresent() async throws {
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-home") { req async throws -> View in
        try await req.view.render(
          "home",
          HomeContext(
            volumeCount: 0, trending: [], tagCloud: [],
            user: LeafUser(
              SessionUser(
                sub: "abc", name: "Alice", email: "alice@example.com", roles: [],
                accessToken: "test-token", expiry: Date().addingTimeInterval(3600))),
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-home") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains("avatar-menu-avatar"))
        #expect(res.body.string.contains("https://www.gravatar.com/avatar/"))
        #expect(res.body.string.contains("d=404"))
        #expect(res.body.string.contains(#"onload="this.nextElementSibling.style.display='none'""#))
        #expect(res.body.string.contains(#"onerror="this.style.display='none'""#))
        #expect(res.body.string.contains("avatar-menu-fallback"))
      }
    }
  }

  @Test("header renders only the fallback letter when the session has no email")
  func headerRendersOnlyFallbackWithoutEmail() async throws {
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-home") { req async throws -> View in
        try await req.view.render(
          "home",
          HomeContext(
            volumeCount: 0, trending: [], tagCloud: [],
            user: LeafUser(
              SessionUser(
                sub: "abc", name: "Alice", email: nil, roles: [], accessToken: "test-token",
                expiry: Date().addingTimeInterval(3600))),
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-home") { res in
        #expect(res.status == .ok)
        #expect(!res.body.string.contains("avatar-menu-avatar"))
        #expect(res.body.string.contains("avatar-menu-fallback"))
      }
    }
  }

  @Test("header renders the Admin link for an admin session")
  func headerRendersAdminLinkForAdminSession() async throws {
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-home") { req async throws -> View in
        try await req.view.render(
          "home",
          HomeContext(
            volumeCount: 0, trending: [], tagCloud: [],
            user: LeafUser(
              SessionUser(
                sub: "abc", name: "Bob", email: nil, roles: ["admin"], accessToken: "test-token",
                expiry: Date().addingTimeInterval(3600))),
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-home") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains(#"href="/admin""#))
        #expect(res.body.string.contains(#"href="/users""#))
      }
    }
  }

  @Test("home page renders a volume card's cover image with an onerror fallback")
  func homeRendersVolumeCoverWithFallback() async throws {
    let volume = VolumeViewModel(
      id: "64c7cf96a3fc8ee7407f9b76", title: "A Glorious Death", description: "", notes: "",
      tags: [], systemNames: [], publisherNames: [], studioNames: [], licenseNames: [])
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-home") { req async throws -> View in
        try await req.view.render(
          "home",
          HomeContext(
            volumeCount: 1, trending: [LeafVolumeCard(volume)], tagCloud: [], user: nil,
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-home") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains("asset/cover/64c7cf96a3fc8ee7407f9b76.svg"))
        #expect(res.body.string.contains(#"onload="this.nextElementSibling.style.display='none'""#))
        #expect(res.body.string.contains(#"onerror="this.style.display='none'""#))
        #expect(res.body.string.contains("card-cover-fallback"))
        #expect(res.body.string.contains("Cover pending"))
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
          "detail",
          DetailContext(
            volume: LeafVolumeDetail(volume), canEdit: false, canUploadCover: false,
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
        #expect(!res.body.string.contains(">Edit<"))
      }
    }
  }

  // MARK: - catalog-volume-cover-upload

  @Test("detail page shows the cover-upload control for an editor/admin session")
  func detailShowsCoverUploadControlWhenCanUploadCover() async throws {
    let volume = VolumeViewModel(
      id: "1", title: "Rusthaven", description: "", notes: "",
      tags: [], systemNames: [], publisherNames: [], studioNames: [], licenseNames: [])
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-detail") { req async throws -> View in
        try await req.view.render(
          "detail",
          DetailContext(
            volume: LeafVolumeDetail(volume), canEdit: false, canUploadCover: true,
            justProposed: false, review: nil,
            conflicts: [], hasConflicts: false, user: nil, meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-detail") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains("cover-upload-input"))
      }
    }
  }

  @Test("detail page hides the cover-upload control for a non-editor session")
  func detailHidesCoverUploadControlWithoutRole() async throws {
    let volume = VolumeViewModel(
      id: "1", title: "Rusthaven", description: "", notes: "",
      tags: [], systemNames: [], publisherNames: [], studioNames: [], licenseNames: [])
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-detail") { req async throws -> View in
        try await req.view.render(
          "detail",
          DetailContext(
            volume: LeafVolumeDetail(volume), canEdit: true, canUploadCover: false,
            justProposed: false, review: nil,
            conflicts: [], hasConflicts: false, user: nil, meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-detail") { res in
        #expect(res.status == .ok)
        #expect(!res.body.string.contains("cover-upload-input"))
      }
    }
  }

  // MARK: - volume-change-review-ui

  private func makeProposal(
    id: String = "prop-1", submittedBy: String = "auth0|submitter",
    diff: [String: FieldChange] = ["title": FieldChange(old: "Old", new: "New", status: "pending")]
  ) -> ProposedChangeSummary {
    ProposedChangeSummary(
      id: id, recordType: "volume", recordId: "1", diff: diff, status: "pending",
      submittedBy: submittedBy, submittedAt: Date(timeIntervalSince1970: 0), reviewedBy: nil,
      reviewedAt: nil, reviewNote: nil)
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
          "detail",
          DetailContext(
            volume: LeafVolumeDetail(volume), canEdit: true, canUploadCover: false,
            justProposed: false, review: nil,
            conflicts: [], hasConflicts: false, user: nil, meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-detail") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains(">Edit<"))
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
          "detail",
          DetailContext(
            // canEdit: true (submitter can propose), but review stays nil - only
            // CatalogController decides to populate it, gated on canReview, not canEdit.
            volume: LeafVolumeDetail(volume), canEdit: true, canUploadCover: false,
            justProposed: false, review: nil,
            conflicts: [], hasConflicts: false, user: nil, meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-detail") { res in
        #expect(res.status == .ok)
        #expect(!res.body.string.contains("Pending Changes"))
      }
    }
  }

  @Test("detail page shows a pending-change indicator and diff for an editor")
  func detailShowsPendingChangeReviewForEditor() async throws {
    let volume = VolumeViewModel(
      id: "1", title: "Rusthaven", description: "", notes: "",
      tags: [], systemNames: [], publisherNames: [], studioNames: [], licenseNames: [])
    let proposal = makeProposal()
    let review = LeafProposalReview(volumeID: "1", pending: [proposal], selected: proposal)
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-detail") { req async throws -> View in
        try await req.view.render(
          "detail",
          DetailContext(
            volume: LeafVolumeDetail(volume), canEdit: false, canUploadCover: false,
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
    let first = makeProposal(id: "prop-1", submittedBy: "auth0|alice")
    let second = makeProposal(id: "prop-2", submittedBy: "auth0|bob")
    let review = LeafProposalReview(volumeID: "1", pending: [first, second], selected: first)
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-detail") { req async throws -> View in
        try await req.view.render(
          "detail",
          DetailContext(
            volume: LeafVolumeDetail(volume), canEdit: false, canUploadCover: false,
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
          "detail",
          DetailContext(
            volume: LeafVolumeDetail(volume), canEdit: false, canUploadCover: false,
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
          "detail",
          DetailContext(
            volume: LeafVolumeDetail(volume), canEdit: false, canUploadCover: false,
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
          "edit",
          EditContext(
            volume: LeafVolumeEditForm(volume), user: nil, meta: await PageMeta.make(req)))
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

  @discardableResult
  private func withMaintenanceModeApp<T>(
    adminAPIURL: String?,
    _ test: (Application) async throws -> T
  ) async throws -> T {
    try await withApp { app in
      app.views.use(.leaf)
      app.backendConfig = BackendConfig(
        catalogAPIURL: "unused", gameSystemsAPIURL: "unused", profilesAPIURL: "unused",
        shelfAPIURL: "unused", adminAPIURL: adminAPIURL)
      app.middleware.use(MaintenanceModeMiddleware())
      app.get("test-home") { req async throws -> View in
        try await req.view.render(
          "home",
          HomeContext(
            volumeCount: 0, trending: [], tagCloud: [], user: nil,
            meta: await PageMeta.make(req)))
      }
      return try await test(app)
    }
  }

  @Test("renders the maintenance page when an active maintenance-mode record exists")
  func maintenancePageRendersWhenActive() async throws {
    let port = 18761
    try await withFakeAdminAPI(
      port: port,
      maintenanceModesJSON: """
        [{
          "scope_type": "platform",
          "scope_value": "",
          "label": "Scheduled downtime",
          "description": "Upgrading the database.",
          "starts_at": "2026-08-01T00:00:00Z",
          "ends_at": "2026-08-01T04:00:00Z"
        }]
        """
    ) {
      try await withMaintenanceModeApp(adminAPIURL: "http://127.0.0.1:\(port)") { app in
        try await app.testing().test(.GET, "test-home") { res in
          #expect(res.status == .serviceUnavailable)
          #expect(res.body.string.contains("Scheduled downtime"))
          #expect(res.body.string.contains("Upgrading the database."))
          #expect(!res.body.string.contains("Vol. count"))
        }
      }
    }
  }

  @Test("renders the normal page when no maintenance-mode record is active")
  func normalPageRendersWhenNoMaintenance() async throws {
    let port = 18762
    try await withFakeAdminAPI(port: port, maintenanceModesJSON: "[]") {
      try await withMaintenanceModeApp(adminAPIURL: "http://127.0.0.1:\(port)") { app in
        try await app.testing().test(.GET, "test-home") { res in
          #expect(res.status == .ok)
          #expect(res.body.string.contains("Vol. count"))
        }
      }
    }
  }

  @Test("renders the normal page when admin-api is unreachable")
  func normalPageRendersWhenAdminAPIUnreachable() async throws {
    try await withMaintenanceModeApp(adminAPIURL: "http://127.0.0.1:1") { app in
      try await app.testing().test(.GET, "test-home") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains("Vol. count"))
      }
    }
  }
}
