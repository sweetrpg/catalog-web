import CatalogAPIClient
import Foundation

struct StudioViewModel {
  let id: String
  let name: String
  let website: String
  let notes: String
  let tags: [String]
  var volumes: [VolumeSummary] = []

  init(id: String, attributes: StudioAttributes) {
    self.id = id
    self.name = attributes.name ?? "Untitled"
    self.website = attributes.website ?? ""
    self.notes = attributes.notes ?? ""
    self.tags = (attributes.tags ?? []).map(\.displayName).filter { !$0.isEmpty }
  }
}
