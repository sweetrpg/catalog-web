import CatalogAPIClient
import Crypto
import Foundation
import Vapor

struct LeafStudioCard: Content {
  let id: String
  let name: String

  init(_ studio: StudioViewModel) {
    self.id = studio.id
    self.name = studio.name
  }
}

struct LeafStudioDetail: Content {
  let id: String
  let name: String
  let website: String
  let hasWebsite: Bool
  let notes: String
  let hasNotes: Bool
  let tags: [String]
  let volumes: [LeafVolumeSummary]
  let hasVolumes: Bool

  init(_ studio: StudioViewModel) {
    self.id = studio.id
    self.name = studio.name
    self.website = studio.website
    self.hasWebsite = !studio.website.isEmpty
    self.notes = studio.notes
    self.hasNotes = !studio.notes.isEmpty
    self.tags = studio.tags
    self.volumes = studio.volumes.map(LeafVolumeSummary.init)
    self.hasVolumes = !studio.volumes.isEmpty
  }
}
