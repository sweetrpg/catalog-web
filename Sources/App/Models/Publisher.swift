import CatalogAPIClient
import Foundation

struct PublisherViewModel {
  let id: String
  let name: String
  let address: String
  let website: String
  let notes: String
  let tags: [String]
  var volumes: [VolumeSummary] = []

  init(id: String, attributes: PublisherAttributes) {
    self.id = id
    self.name = attributes.name ?? "Untitled"
    self.address = attributes.address ?? ""
    self.website = attributes.website ?? ""
    self.notes = attributes.notes ?? ""
    self.tags = (attributes.tags ?? []).map(\.displayName).filter { !$0.isEmpty }
  }
}
