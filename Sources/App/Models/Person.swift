import CatalogAPIClient
import Foundation

struct PersonViewModel {
  let id: String
  let name: String
  let notes: String
  let tags: [String]
  var volumes: [VolumeSummary] = []

  init(id: String, attributes: PersonAttributes) {
    self.id = id
    self.name = attributes.displayName
    self.notes = attributes.notes ?? ""
    self.tags = (attributes.tags ?? []).map(\.displayName).filter { !$0.isEmpty }
  }
}
