import CatalogAPIClient
import Crypto
import Foundation
import Vapor

struct LeafPersonCard: Content {
  let id: String
  let name: String

  init(_ person: PersonViewModel) {
    self.id = person.id
    self.name = person.name
  }
}

struct LeafPersonDetail: Content {
  let id: String
  let name: String
  let notes: String
  let hasNotes: Bool
  let tags: [String]
  let volumes: [LeafVolumeSummary]
  let hasVolumes: Bool

  init(_ person: PersonViewModel) {
    self.id = person.id
    self.name = person.name
    self.notes = person.notes
    self.hasNotes = !person.notes.isEmpty
    self.tags = person.tags
    self.volumes = person.volumes.map(LeafVolumeSummary.init)
    self.hasVolumes = !person.volumes.isEmpty
  }
}
