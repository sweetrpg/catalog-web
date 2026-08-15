import CatalogAPIClient
import Crypto
import Foundation
import Vapor


struct LeafVolumeCard: Content {
  let id: String
  let title: String
  let tagChips: [String]
  let coverAssetPath: String

  init(_ volume: VolumeViewModel) {
    self.id = volume.id
    self.title = volume.title
    self.tagChips = volume.tagChips
    self.coverAssetPath = volume.coverAssetPath
  }
}

struct LeafVolumeDetail: Content {
  let id: String
  let title: String
  let description: String
  let hasDescription: Bool
  let notes: String
  let hasNotes: Bool
  let tags: [String]
  let systemNames: [String]
  let hasSystemNames: Bool
  let publisherNames: [String]
  let hasPublisherNames: Bool
  let publisherRefs: [LeafEntityRef]
  let studioNames: [String]
  let hasStudioNames: Bool
  let studioRefs: [LeafEntityRef]
  let licenseNames: [String]
  let hasLicenseNames: Bool
  let licenseRefs: [LeafEntityRef]
  let credits: [LeafCredit]
  let hasCredits: Bool
  let properties: [LeafProperty]
  let hasProperties: Bool
  let reviews: [LeafReview]
  let hasReviews: Bool
  let coverAssetPath: String
  let samplePaths: [String]
  let hasSamples: Bool

  init(_ volume: VolumeViewModel) {
    self.id = volume.id
    self.title = volume.title
    self.description = volume.description
    self.hasDescription = !volume.description.isEmpty
    self.notes = volume.notes
    self.hasNotes = !volume.notes.isEmpty
    self.tags = volume.tags
    self.systemNames = volume.systemNames
    self.hasSystemNames = !volume.systemNames.isEmpty
    self.publisherNames = volume.publisherNames
    self.hasPublisherNames = !volume.publisherNames.isEmpty
    self.publisherRefs = volume.publisherRefs.map(LeafEntityRef.init)
    self.studioNames = volume.studioNames
    self.hasStudioNames = !volume.studioNames.isEmpty
    self.studioRefs = volume.studioRefs.map(LeafEntityRef.init)
    self.licenseNames = volume.licenseNames
    self.hasLicenseNames = !volume.licenseNames.isEmpty
    self.licenseRefs = volume.licenseRefs.map(LeafEntityRef.init)
    self.credits = volume.credits.map(LeafCredit.init)
    self.hasCredits = !volume.credits.isEmpty
    self.properties = volume.properties.map(LeafProperty.init)
    self.hasProperties = !volume.properties.isEmpty
    self.reviews = volume.reviews.map(LeafReview.init)
    self.hasReviews = !volume.reviews.isEmpty
    self.coverAssetPath = volume.coverAssetPath
    self.samplePaths = volume.samplePaths
    self.hasSamples = !volume.samplePaths.isEmpty
  }
}

struct LeafVolumeEditForm: Content {
  let id: String
  let title: String
  let description: String
  let hasDescription: Bool
  let notes: String
  let hasNotes: Bool
  /// The current session's cover: a staged one if the user has uploaded one this session,
  /// otherwise the volume's existing live cover.
  let coverAssetPath: String
  /// The signed-in user's Auth0 subject - the id staged assets are filed under
  /// (`cover-staged/<sub>`, see docs/frontend-conventions.md's staging convention in
  /// sweetrpg/platform) and this page's JS needs it to build the upload URL.
  let userSub: String
  /// The full publisher candidate list, JSON-encoded for the page's own JS to filter
  /// client-side (task 7.1) - no search endpoint, existing entities only, per design.md.
  let publisherOptionsJSON: String
  let selectedPublishers: [LeafNamedOption]
  let hasSelectedPublishers: Bool
  let studioOptionsJSON: String
  let selectedStudios: [LeafNamedOption]
  let hasSelectedStudios: Bool
  /// The full person candidate list for the contributor dialog's person picker (task 8.1) -
  /// same client-side-filtering, no-create-new rationale as publishers/studios.
  let personOptionsJSON: String
  /// Every contribution type already in use, JSON-encoded (plain strings, not id/name pairs -
  /// a vocabulary value has no separate id). Available to any edit-capable role.
  let contributionTypeOptionsJSON: String
  /// `true` for editor/admin sessions only - gates the "add a new contribution type" affordance
  /// in the contributor dialog. A submitter sees the same vocabulary but select-only.
  let canAddContributionType: Bool
  let selectedCredits: [LeafSelectedCredit]
  let hasSelectedCredits: Bool
  /// Every property name already in use, JSON-encoded (plain strings, same shape as
  /// `contributionTypeOptionsJSON`).
  let propertyNameOptionsJSON: String
  /// `true` for editor/admin sessions only - gates the "add a new property name" affordance,
  /// same rationale as `canAddContributionType`.
  let canAddPropertyName: Bool
  let selectedProperties: [LeafProperty]
  let hasSelectedProperties: Bool
  /// Every format value in use, JSON-encoded (plain strings). Only ever fetched/populated for
  /// an editor/admin caller - a submitter's token can't even list this vocabulary (see
  /// `volume-format-selector`'s spec, unlike contribution-type/property-name which submitters
  /// can read).
  let formatOptionsJSON: String
  /// `true` for editor/admin sessions only - gates the *entire* format selector, not just an
  /// add-new affordance within it (the one field where the whole control, not just growing its
  /// vocabulary, is editor/admin-only).
  let canSetFormat: Bool
  let selectedFormat: String
  let hasSelectedFormat: Bool
  /// The volume's existing live samples - shown read-only for context; this page has no way to
  /// remove or reorder them individually (see `edit.leaf`'s note to the user: uploading any new
  /// sample below replaces this entire set on save, matching `finalize-session`'s actual
  /// promote-the-whole-staged-set behavior - there is no way to carry an existing live sample
  /// into a fresh staged set without re-uploading it).
  let livingSamplePaths: [String]
  let hasLivingSamples: Bool
  /// Samples staged this session (`sample-staged/<userSub>-<n>`) - what finalize will promote to
  /// live, replacing `livingSamplePaths` entirely, if this is non-empty.
  let stagedSamples: [LeafStagedAsset]
  let hasStagedSamples: Bool

  init(
    volume: VolumeViewModel, session: EditSession, userSub: String,
    publisherOptions: [(id: String, name: String)] = [],
    studioOptions: [(id: String, name: String)] = [],
    personOptions: [(id: String, name: String)] = [],
    contributionTypeOptions: [String] = [],
    canAddContributionType: Bool = false,
    propertyNameOptions: [String] = [],
    canAddPropertyName: Bool = false,
    formatOptions: [String] = [],
    canSetFormat: Bool = false
  ) {
    self.id = volume.id
    self.title = session.stringField("title") ?? volume.title
    self.description = session.stringField("description") ?? volume.description
    self.hasDescription = !self.description.isEmpty
    self.notes = session.stringField("notes") ?? volume.notes
    self.hasNotes = !self.notes.isEmpty
    self.userSub = userSub
    if let staged = session.stagedCoverAssetId {
      self.coverAssetPath = "asset/cover-staged/\(staged)"
    } else {
      self.coverAssetPath = volume.coverAssetPath
    }

    let publisherByID = Dictionary(uniqueKeysWithValues: publisherOptions)
    let selectedPublisherIds = session.stringArrayField("publisherIds") ?? volume.publisherIds
    self.selectedPublishers = selectedPublisherIds.map {
      LeafNamedOption(id: $0, name: publisherByID[$0] ?? "Unknown publisher")
    }
    self.hasSelectedPublishers = !self.selectedPublishers.isEmpty
    self.publisherOptionsJSON =
      Self.encodeOptions(publisherOptions.map { LeafNamedOption(id: $0.id, name: $0.name) })

    let studioByID = Dictionary(uniqueKeysWithValues: studioOptions)
    let selectedStudioIds = session.stringArrayField("studioIds") ?? volume.studioIds
    self.selectedStudios = selectedStudioIds.map {
      LeafNamedOption(id: $0, name: studioByID[$0] ?? "Unknown studio")
    }
    self.hasSelectedStudios = !self.selectedStudios.isEmpty
    self.studioOptionsJSON =
      Self.encodeOptions(studioOptions.map { LeafNamedOption(id: $0.id, name: $0.name) })

    self.personOptionsJSON =
      Self.encodeOptions(personOptions.map { LeafNamedOption(id: $0.id, name: $0.name) })
    self.contributionTypeOptionsJSON =
      (try? JSONEncoder().encode(contributionTypeOptions)).flatMap {
        String(data: $0, encoding: .utf8)
      } ?? "[]"
    self.canAddContributionType = canAddContributionType

    let personByID = Dictionary(uniqueKeysWithValues: personOptions)
    if let sessionCredits = session.objectArrayField("credits") {
      self.selectedCredits = sessionCredits.compactMap { entry in
        guard let personId = entry["personId"], let contributionType = entry["contributionType"]
        else { return nil }
        return LeafSelectedCredit(
          personId: personId, personName: personByID[personId] ?? "Unknown person",
          contributionType: contributionType)
      }
    } else {
      self.selectedCredits = volume.credits.map {
        LeafSelectedCredit(personId: $0.personId, personName: $0.person, contributionType: $0.role)
      }
    }
    self.hasSelectedCredits = !self.selectedCredits.isEmpty

    self.propertyNameOptionsJSON =
      (try? JSONEncoder().encode(propertyNameOptions)).flatMap {
        String(data: $0, encoding: .utf8)
      } ?? "[]"
    self.canAddPropertyName = canAddPropertyName

    if let sessionProperties = session.objectArrayField("properties") {
      self.selectedProperties = sessionProperties.compactMap { entry in
        guard let name = entry["name"], let value = entry["value"] else { return nil }
        return LeafProperty((name: name, value: value))
      }
    } else {
      self.selectedProperties = volume.properties.map(LeafProperty.init)
    }
    self.hasSelectedProperties = !self.selectedProperties.isEmpty

    self.formatOptionsJSON =
      (try? JSONEncoder().encode(formatOptions)).flatMap { String(data: $0, encoding: .utf8) }
      ?? "[]"
    self.canSetFormat = canSetFormat
    self.selectedFormat = session.stringField("format") ?? volume.format
    self.hasSelectedFormat = !self.selectedFormat.isEmpty

    self.livingSamplePaths = volume.samplePaths
    self.hasLivingSamples = !volume.samplePaths.isEmpty
    self.stagedSamples = (session.sampleAssetIds ?? []).map {
      LeafStagedAsset(id: $0, path: "asset/sample-staged/\($0)")
    }
    self.hasStagedSamples = !self.stagedSamples.isEmpty
  }

  private static func encodeOptions(_ options: [LeafNamedOption]) -> String {
    (try? JSONEncoder().encode(options)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
  }
}


struct LeafVolumeSummary: Content {
  let id: String
  let title: String

  init(_ summary: VolumeSummary) {
    self.id = summary.id
    self.title = summary.title
  }
}
