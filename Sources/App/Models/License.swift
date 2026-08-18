import CatalogAPIClient
import Foundation

struct LicenseViewModel {
  let id: String
  let title: String
  let shortTitle: String
  let version: String
  let deed: String
  let legalCode: String
  let website: String
  let status: String
  let availability: String
  let notes: String
  let tags: [String]
  var properties: [(name: String, value: String)] = []
  var volumes: [VolumeSummary] = []

  init(id: String, attributes: LicenseAttributes) {
    self.id = id
    self.title = attributes.title ?? "Untitled"
    self.shortTitle = attributes.shortTitle ?? ""
    self.version = attributes.version ?? ""
    self.deed = attributes.deed ?? ""
    self.legalCode = attributes.legalCode ?? ""
    self.website = attributes.website ?? ""
    self.status = attributes.status ?? ""
    self.availability = attributes.availability ?? ""
    self.notes = attributes.notes ?? ""
    self.tags = (attributes.tags ?? []).map(\.displayName).filter { !$0.isEmpty }
    self.properties = (attributes.properties ?? []).map { ($0.name, $0.value) }
  }
}
