import Testing
import VaporTesting

@testable import App

/// The edit page's upload scripts are inline, so these assert on the rendered page. Behavior tests
/// arrive when the scripts move to shared-web (PADR-0045).
@Suite("Staged uploads")
struct StagedUploadTests {
  private func editPage(stagedCover: String?) async throws -> String {
    let volume = VolumeViewModel(
      id: "1", title: "Rusthaven", description: "", notes: "",
      tags: [], systemNames: [], publisherNames: [], studioNames: [], licenseNames: [])
    var session = testEditSession(for: volume)
    session.stagedCoverAssetId = stagedCover
    var body = ""
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-edit") { req async throws -> View in
        try await req.view.render(
          "volumes/edit",
          EditContext(
            volume: try LeafVolumeEditForm(
              volume: volume, session: session, userSub: "auth0-tester", req: req),
            canUploadCover: true, submitError: nil, user: nil,
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-edit") { body = $0.body.string }
    }
    return body
  }

  @Test("each staged sample upload gets a time-based id")
  func sampleIdsAreTimeBased() async throws {
    let body = try await editPage(stagedCover: nil)
    #expect(body.contains("var id = userSub + '-' + Date.now();"))
    #expect(!body.contains("nextIndex"))
  }

  @Test(
    "the discard form says whether this session staged a cover",
    arguments: [(String?.some("auth0-tester"), "true"), (nil, "false")])
  func discardFormCarriesStagedState(stagedCover: String?, expected: String) async throws {
    let body = try await editPage(stagedCover: stagedCover)
    let form = try #require(
      body.split(separator: "\n").first { $0.contains(#"id="discard-form""#) })
    #expect(form.contains(#"data-cover-staged="\#(expected)""#))
  }

  @Test("discard deletes only a staged cover, and upload and remove keep that state current")
  func discardScriptIsGuarded() async throws {
    let body = try await editPage(stagedCover: nil)
    #expect(body.contains("if (form.dataset.coverStaged !== 'true') return;"))
    #expect(body.contains("discardForm.dataset.coverStaged = 'true';"))
    #expect(body.contains("discardForm.dataset.coverStaged = 'false';"))
  }
}
