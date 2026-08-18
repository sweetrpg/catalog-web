import CatalogAPIClient
import Crypto
import Foundation
import Vapor

struct LeafLicenseCard: Content {
  let id: String
  let title: String

  init(_ license: LicenseViewModel) {
    self.id = license.id
    self.title = license.title
  }
}

struct LeafLicenseDetail: Content {
  let id: String
  let title: String
  let shortTitle: String
  let hasShortTitle: Bool
  let version: String
  let hasVersion: Bool
  let deed: String
  let hasDeed: Bool
  let legalCode: String
  let hasLegalCode: Bool
  let website: String
  let hasWebsite: Bool
  let status: String
  let hasStatus: Bool
  let availability: String
  let hasAvailability: Bool
  let notes: String
  let hasNotes: Bool
  let tags: [String]
  let hasTags: Bool
  let properties: [LeafProperty]
  let hasProperties: Bool
  let volumes: [LeafVolumeSummary]
  let hasVolumes: Bool

  init(_ license: LicenseViewModel) {
    self.id = license.id
    self.title = license.title
    self.shortTitle = license.shortTitle
    self.hasShortTitle = !license.shortTitle.isEmpty
    self.version = license.version
    self.hasVersion = !license.version.isEmpty
    self.deed = license.deed
    self.hasDeed = !license.deed.isEmpty
    self.legalCode = license.legalCode
    self.hasLegalCode = !license.legalCode.isEmpty
    self.website = license.website
    self.hasWebsite = !license.website.isEmpty
    self.status = license.status
    self.hasStatus = !license.status.isEmpty
    self.availability = license.availability
    self.hasAvailability = !license.availability.isEmpty
    self.notes = license.notes
    self.hasNotes = !license.notes.isEmpty
    self.tags = license.tags
    self.hasTags = !license.tags.isEmpty
    self.properties = license.properties.map(LeafProperty.init)
    self.hasProperties = !license.properties.isEmpty
    self.volumes = license.volumes.map(LeafVolumeSummary.init)
    self.hasVolumes = !license.volumes.isEmpty
  }
}
