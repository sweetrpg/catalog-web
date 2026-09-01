import CatalogAPIClient
import Foundation
import Testing
import VaporTesting

@testable import App

@Suite("Credit grouping")
struct CreditGroupingTests {
  @Test("a person with one role produces one group with that single role")
  func singlePersonSingleRole() {
    let groups = groupCreditsByPerson([
      (personId: "p1", role: "writer", person: "Ada Vale")
    ])
    #expect(groups.count == 1)
    #expect(groups[0].personId == "p1")
    #expect(groups[0].person == "Ada Vale")
    #expect(groups[0].rolesLabel == "writer")
  }

  @Test("a person with multiple roles collapses into one group, roles joined in first-seen order")
  func singlePersonMultipleRoles() {
    let groups = groupCreditsByPerson([
      (personId: "p1", role: "writer", person: "Ryan Chaddock"),
      (personId: "p1", role: "editor", person: "Ryan Chaddock"),
      (personId: "p1", role: "artist", person: "Ryan Chaddock"),
    ])
    #expect(groups.count == 1)
    #expect(groups[0].rolesLabel == "writer, editor, artist")
  }

  @Test("distinct persons stay separate, in first-seen order")
  func multipleDistinctPersons() {
    let groups = groupCreditsByPerson([
      (personId: "p2", role: "writer", person: "Bea Cole"),
      (personId: "p1", role: "artist", person: "Ada Vale"),
      (personId: "p2", role: "editor", person: "Bea Cole"),
    ])
    #expect(groups.map(\.personId) == ["p2", "p1"])
    #expect(groups[0].rolesLabel == "writer, editor")
    #expect(groups[1].rolesLabel == "artist")
  }

  @Test("a repeated identical (person, role) pair is not duplicated in the label")
  func deduplicatesIdenticalRole() {
    let groups = groupCreditsByPerson([
      (personId: "p1", role: "writer", person: "Ada Vale"),
      (personId: "p1", role: "writer", person: "Ada Vale"),
    ])
    #expect(groups.count == 1)
    #expect(groups[0].rolesLabel == "writer")
  }

  @Test("LeafVolumeDetail collapses a person's multiple roles into a single credit line")
  func detailPageGroupsCreditsByPerson() async throws {
    var volume = VolumeViewModel(
      id: "1", title: "Rusthaven", description: "", notes: "",
      tags: [], systemNames: [], publisherNames: [], studioNames: [], licenseNames: [])
    volume.credits = [
      (personId: "person-1", role: "writer", person: "Ryan Chaddock"),
      (personId: "person-1", role: "editor", person: "Ryan Chaddock"),
      (personId: "person-1", role: "artist", person: "Ryan Chaddock"),
    ]
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
        let body = res.body.string
        #expect(body.contains("&mdash; writer, editor, artist"))
        // One credit line for the person, not three.
        #expect(body.components(separatedBy: #"href="/persons/person-1""#).count == 2)
      }
    }
  }
}
