import CatalogAPIClient
import Crypto
import Foundation
import Vapor

struct LeafPublisherCard: Content {
  let id: String
  let name: String
  let volumeCountLabel: String

  init(_ publisher: PublisherViewModel, volumeCountLabel: String) {
    self.id = publisher.id
    self.name = publisher.name
    self.volumeCountLabel = volumeCountLabel
  }
}

struct LeafPublisherDetail: Content {
  let id: String
  let name: String
  let address: String
  let hasAddress: Bool
  let website: String
  let hasWebsite: Bool
  let notes: String
  let hasNotes: Bool
  let tags: [String]
  let volumes: [LeafVolumeSummary]
  let hasVolumes: Bool

  init(_ publisher: PublisherViewModel) {
    self.id = publisher.id
    self.name = publisher.name
    self.address = publisher.address
    self.hasAddress = !publisher.address.isEmpty
    self.website = publisher.website
    self.hasWebsite = !publisher.website.isEmpty
    self.notes = publisher.notes
    self.hasNotes = !publisher.notes.isEmpty
    self.tags = publisher.tags
    self.volumes = publisher.volumes.map(LeafVolumeSummary.init)
    self.hasVolumes = !publisher.volumes.isEmpty
  }
}
