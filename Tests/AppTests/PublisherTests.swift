import AdminAPIClient
import CatalogAPIClient
import Foundation
import Redis
import Testing
import VaporTesting

@testable import App

@Suite("Publisher")
struct PublisherTests {

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
}
