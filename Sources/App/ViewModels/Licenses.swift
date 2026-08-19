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

/// The license edit page's context - `EntityEditContext` plus the two fields the generic entity
/// edit form doesn't have (sweetrpg/catalog-web#121): a free-text `tags` value and a
/// volume-association picker. Not folded into `EntityEditContext` itself since publisher/studio/
/// person don't need either.
struct LicenseEditContext: Content {
  let id: String
  let backPath: String
  let submitPath: String
  let fields: [LeafEntityFieldInput]
  /// Comma-joined for a plain text input - license tags are free-text labels (no shared
  /// vocabulary to pick from, unlike publisher/studio on the volume edit page), so a
  /// type-to-filter picker would have nothing to filter against.
  let tagsValue: String
  /// The volumes picker writes directly to volume records with no review step (see
  /// sweetrpg/catalog-api#220), so it's only shown to a session with review rights - a
  /// submitter still gets the rest of this form (tags included, which does go through the
  /// normal review flow).
  let canManageVolumes: Bool
  let selectedVolumes: [LeafNamedOption]
  let volumeOptionsJSON: String
  let user: LeafUser?
  let meta: PageMeta

  init(
    base: EntityEditContext, tags: [String], canManageVolumes: Bool,
    selectedVolumes: [VolumeSummary], allVolumes: [(id: String, title: String)]
  ) {
    self.id = base.id
    self.backPath = base.backPath
    self.submitPath = base.submitPath
    self.fields = base.fields
    self.tagsValue = tags.joined(separator: ", ")
    self.canManageVolumes = canManageVolumes
    self.selectedVolumes = selectedVolumes.map { LeafNamedOption(id: $0.id, name: $0.title) }
    let options = allVolumes.map { LeafNamedOption(id: $0.id, name: $0.title) }
    self.volumeOptionsJSON =
      (try? JSONEncoder().encode(options)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    self.user = base.user
    self.meta = base.meta
  }
}
