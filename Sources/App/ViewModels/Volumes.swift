import CatalogAPIClient
import Crypto
import Foundation
import Ink
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
  /// The description rendered from Markdown (line breaks, emphasis, lists) - templates render
  /// this via #unsafeHTML rather than the raw `description` field.
  let descriptionHTML: String
  let hasDescription: Bool
  let notes: String
  let hasNotes: Bool
  let tags: [String]
  let hasTags: Bool
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

  init(_ volume: VolumeViewModel, req: Request) throws {
    self.id = volume.id
    self.title = volume.title
    self.description = volume.description
    self.descriptionHTML = MarkdownParser().html(from: volume.description)
    self.hasDescription = !volume.description.isEmpty
    self.notes = volume.notes
    self.hasNotes = !volume.notes.isEmpty
    self.tags = volume.tags
    self.hasTags = !volume.tags.isEmpty
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
    self.properties = try volume.properties.map {
      LeafProperty(
        name: $0.name, value: $0.value, displayLabel: try propertyDisplayLabel($0.name, req: req))
    }
    self.hasProperties = !volume.properties.isEmpty
    self.reviews = volume.reviews.map(LeafReview.init)
    self.hasReviews = !volume.reviews.isEmpty
    self.coverAssetPath = volume.coverAssetPath
    self.samplePaths = volume.samplePaths
    self.hasSamples = !volume.samplePaths.isEmpty
  }
}

/// One optional field (beyond the required `name`) shown in an entity-creation popup - see
/// `LeafEntityCreatePopupConfig`.
struct LeafEntityCreatePopupField: Content {
  let key: String
  let label: String
}

/// Configures one rendering of `partials/entity-create-popup.leaf` (add-entity-popup-volume-edit,
/// task 2.1/4.1) - `LeafVolumeEditForm` builds one of these per creatable entity type (publisher,
/// studio, person) when `canCreateEntities` is true, empty otherwise so a submitter's page never
/// even renders the markup.
struct LeafEntityCreatePopupConfig: Content {
  let popupID: String
  let popupTitle: String
  let entityType: String
  let volumeID: String
  let fields: [LeafEntityCreatePopupField]
  /// The optional fields' keys alone, JSON-encoded - the popup's own script reads this to know
  /// which `#(popupID)-<key>` inputs to collect without re-deriving it from `fields` in JS.
  let fieldKeysJSON: String

  init(
    popupID: String, popupTitle: String, entityType: String, volumeID: String,
    fields: [LeafEntityCreatePopupField]
  ) {
    self.popupID = popupID
    self.popupTitle = popupTitle
    self.entityType = entityType
    self.volumeID = volumeID
    self.fields = fields
    self.fieldKeysJSON =
      (try? JSONEncoder().encode(fields.map(\.key))).flatMap { String(data: $0, encoding: .utf8) }
      ?? "[]"
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
  /// The volume's live cover, ignoring any staged replacement - what the "remove staged cover"
  /// control reverts the preview to.
  let liveCoverPath: String
  /// `true` when the session already has a staged cover on page load (a prior visit staged one
  /// without finalizing) - shows the "remove staged cover" control immediately rather than only
  /// after a fresh upload this same page view.
  let hasStagedCover: Bool
  /// The signed-in user's Auth0 subject - the id staged assets are filed under
  /// (`cover-staged/<sub>`, see docs/frontend-conventions.md's staging convention in
  /// sweetrpg/platform) and this page's JS needs it to build the upload URL.
  let userSub: String
  /// The full publisher candidate list, JSON-encoded for the page's own JS to filter
  /// client-side (task 7.1) - no search endpoint, existing entities only, per design.md.
  let systemOptionsJSON: String
  let selectedSystems: [LeafNamedOption]
  let hasSelectedSystems: Bool
  let publisherOptionsJSON: String
  let selectedPublishers: [LeafNamedOption]
  let hasSelectedPublishers: Bool
  let studioOptionsJSON: String
  let selectedStudios: [LeafNamedOption]
  let hasSelectedStudios: Bool
  /// `true` for editor/admin sessions only - gates the "Create new" action in the publisher,
  /// studio, and contributor person pickers (add-entity-popup-volume-edit). Narrower than
  /// `canAddContributionType`/`canAddPropertyName`/`canAddTag`, which are also editor/admin
  /// only but gate a different, unrelated action.
  let canCreateEntities: Bool
  /// One config per creatable entity type, empty when `canCreateEntities` is false - see
  /// `LeafEntityCreatePopupConfig`.
  let entityCreatePopups: [LeafEntityCreatePopupConfig]
  /// The full person candidate list for the contributor dialog's person picker (task 8.1) -
  /// same client-side-filtering rationale as publishers/studios, though unlike those this one
  /// does offer a "Create new" action for editor/admin (see `canCreateEntities`).
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
  /// The volume's free-text tags (session-staged values win over live ones, same as every
  /// other field) - plain strings, not references to entities.
  let selectedTags: [String]
  let hasTags: Bool
  /// Every known tag value from the shared "tag" vocabulary, JSON-encoded (plain strings) -
  /// the page's own JS filters this client-side; new values are allowed regardless.
  let tagOptionsJSON: String
  /// `true` for editor/admin sessions only - gates growing the shared tag vocabulary with a
  /// newly typed value, same rationale as `canAddContributionType`.
  let canAddTag: Bool
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
    volume: VolumeViewModel, session: EditSession, userSub: String, req: Request,
    systemOptions: [(id: String, name: String)] = [],
    publisherOptions: [(id: String, name: String)] = [],
    studioOptions: [(id: String, name: String)] = [],
    personOptions: [(id: String, name: String)] = [],
    contributionTypeOptions: [String] = [],
    canAddContributionType: Bool = false,
    propertyNameOptions: [String] = [],
    canAddPropertyName: Bool = false,
    tagOptions: [String] = [],
    canAddTag: Bool = false,
    canCreateEntities: Bool = false
  ) throws {
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
    self.liveCoverPath = volume.coverAssetPath
    self.hasStagedCover = session.stagedCoverAssetId != nil

    let systemByID = Dictionary(uniqueKeysWithValues: systemOptions)
    let deletedSystemByID = Dictionary(
      uniqueKeysWithValues: volume.systemRefs.filter(\.isDeleted).map { ($0.id, $0.name) })
    let selectedSystemIds = session.stringArrayField("systemIds") ?? volume.systemIds
    self.selectedSystems = selectedSystemIds.map { id in
      if let name = systemByID[id] { return LeafNamedOption(id: id, name: name) }
      if let name = deletedSystemByID[id] {
        return LeafNamedOption(id: id, name: "\(name) (deleted)")
      }
      return LeafNamedOption(id: id, name: "Unknown system")
    }
    self.hasSelectedSystems = !self.selectedSystems.isEmpty
    self.systemOptionsJSON =
      Self.encodeOptions(systemOptions.map { LeafNamedOption(id: $0.id, name: $0.name) })

    // Falls back to volume.publisherRefs/studioRefs/systemRefs (resolved via
    // resolveDeletedReferences before this init is called) for a currently-selected id that's
    // missing from publisherOptions/studioOptions/systemOptions because it's soft-deleted since
    // the volume linked it - labels "(deleted)" instead of "Unknown publisher"/"Unknown studio"
    // (task 4.1).
    let publisherByID = Dictionary(uniqueKeysWithValues: publisherOptions)
    let deletedPublisherByID = Dictionary(
      uniqueKeysWithValues: volume.publisherRefs.filter(\.isDeleted).map { ($0.id, $0.name) })
    let selectedPublisherIds = session.stringArrayField("publisherIds") ?? volume.publisherIds
    self.selectedPublishers = selectedPublisherIds.map { id in
      if let name = publisherByID[id] { return LeafNamedOption(id: id, name: name) }
      if let name = deletedPublisherByID[id] {
        return LeafNamedOption(id: id, name: "\(name) (deleted)")
      }
      return LeafNamedOption(id: id, name: "Unknown publisher")
    }
    self.hasSelectedPublishers = !self.selectedPublishers.isEmpty
    self.publisherOptionsJSON =
      Self.encodeOptions(publisherOptions.map { LeafNamedOption(id: $0.id, name: $0.name) })

    let studioByID = Dictionary(uniqueKeysWithValues: studioOptions)
    let deletedStudioByID = Dictionary(
      uniqueKeysWithValues: volume.studioRefs.filter(\.isDeleted).map { ($0.id, $0.name) })
    let selectedStudioIds = session.stringArrayField("studioIds") ?? volume.studioIds
    self.selectedStudios = selectedStudioIds.map { id in
      if let name = studioByID[id] { return LeafNamedOption(id: id, name: name) }
      if let name = deletedStudioByID[id] {
        return LeafNamedOption(id: id, name: "\(name) (deleted)")
      }
      return LeafNamedOption(id: id, name: "Unknown studio")
    }
    self.hasSelectedStudios = !self.selectedStudios.isEmpty
    self.studioOptionsJSON =
      Self.encodeOptions(studioOptions.map { LeafNamedOption(id: $0.id, name: $0.name) })

    self.canCreateEntities = canCreateEntities
    if canCreateEntities {
      let l10n = I18n.table(for: req)
      let notesLabel = l10n["volume_edit.entity_notes_label"] ?? "Notes"
      let websiteLabel = l10n["volume_edit.entity_website_label"] ?? "Website"
      self.entityCreatePopups = [
        LeafEntityCreatePopupConfig(
          popupID: "publisher-create-popup",
          popupTitle: l10n["volume_edit.new_publisher_title"] ?? "New Publisher",
          entityType: "publisher", volumeID: volume.id,
          fields: [
            LeafEntityCreatePopupField(key: "notes", label: notesLabel),
            LeafEntityCreatePopupField(key: "website", label: websiteLabel),
          ]),
        LeafEntityCreatePopupConfig(
          popupID: "studio-create-popup",
          popupTitle: l10n["volume_edit.new_studio_title"] ?? "New Studio",
          entityType: "studio", volumeID: volume.id,
          fields: [
            LeafEntityCreatePopupField(key: "notes", label: notesLabel),
            LeafEntityCreatePopupField(key: "website", label: websiteLabel),
          ]),
        LeafEntityCreatePopupConfig(
          popupID: "person-create-popup",
          popupTitle: l10n["volume_edit.new_person_title"] ?? "New Person",
          entityType: "person", volumeID: volume.id,
          fields: [
            LeafEntityCreatePopupField(key: "notes", label: notesLabel)
          ]),
      ]
    } else {
      self.entityCreatePopups = []
    }
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
      self.selectedProperties = try sessionProperties.compactMap { entry in
        guard let name = entry["name"], let value = entry["value"] else { return nil }
        return LeafProperty(
          name: name, value: value, displayLabel: try propertyDisplayLabel(name, req: req))
      }
    } else {
      self.selectedProperties = try volume.properties.map {
        LeafProperty(
          name: $0.name, value: $0.value,
          displayLabel: try propertyDisplayLabel($0.name, req: req))
      }
    }
    self.hasSelectedProperties = !self.selectedProperties.isEmpty

    self.selectedTags = session.stringArrayField("tags") ?? volume.tags
    self.hasTags = !self.selectedTags.isEmpty
    self.tagOptionsJSON =
      (try? JSONEncoder().encode(tagOptions)).flatMap {
        String(data: $0, encoding: .utf8)
      } ?? "[]"
    self.canAddTag = canAddTag

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
