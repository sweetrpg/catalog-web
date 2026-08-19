import CatalogAPIClient
import Crypto
import Foundation
import Vapor

struct LeafLicenseCard: Content {
  let id: String
  let title: String
  // Pre-localized ("3 volumes"/"1 volume" in en) rather than a raw count + template-side
  // string-hacking - see licenses.browse.volume_count in Resources/Localizations/en.json.
  let volumeCountLabel: String
  // "Not active" reads as "not Accepted" - Draft/Deprecated/Retired/unset all get the badge,
  // only Accepted doesn't. See licenseStatusOptions in LicensesController.swift.
  let isNotAccepted: Bool

  init(_ license: LicenseViewModel, volumeCountLabel: String) {
    self.id = license.id
    self.title = license.title
    self.volumeCountLabel = volumeCountLabel
    self.isNotAccepted = license.status != "Accepted"
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

  init(_ license: LicenseViewModel, req: Request) throws {
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
    self.properties = try license.properties.map {
      LeafProperty(
        name: $0.name, value: $0.value, displayLabel: try propertyDisplayLabel($0.name, req: req))
    }
    self.hasProperties = !license.properties.isEmpty
    self.volumes = license.volumes.map(LeafVolumeSummary.init)
    self.hasVolumes = !license.volumes.isEmpty
  }
}
