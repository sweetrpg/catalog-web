import CatalogAPIClient
import Crypto
import Foundation
import Vapor

// MARK: - Leaf page contexts

/// Concrete, per-page Encodable structs - not `[String: Encodable]` dictionaries. Swift's
/// `Dictionary` only conditionally conforms to `Encodable` when its `Value` is *concretely*
/// `Encodable`; `any Encodable` as the value type doesn't satisfy that, so a dictionary typed
/// `[String: Encodable]` does not itself conform to `Encodable` and can't be passed to
/// `req.view.render`, which requires a real `Encodable` context type.

struct HomeContext: Content {
  let statCards: [LeafTypeStatsCard]
  let tagCloud: [LeafTag]
  let user: LeafUser?
  let meta: PageMeta
}

/// One entity type's landing-page-summary card (catalog-landing-page-summary): total count plus
/// a link to the most recently added/updated entity, or an empty-state when the type has zero
/// records - see spec's "degrades gracefully for an empty entity type" requirement.
///
/// `detailPathPrefix` is `nil` for a type with no catalog-web detail page of its own (systems -
/// relations onto a volume only, no `/systems/:id` route exists, matching this app's existing
/// "systems have no dedicated pages" scoping elsewhere) - `hasDetailLink` gates the template
/// between a link and plain text for "most recent" so this doesn't render a dead link.
struct LeafTypeStatsCard: Content {
  let label: String
  let count: Int
  let hasDetailLink: Bool
  let detailPathPrefix: String
  let hasMostRecent: Bool
  let mostRecentID: String
  let mostRecentName: String
  let lastUpdatedLabel: String

  init(label: String, detailPathPrefix: String?, stats: TypeStats) {
    self.label = label
    self.count = stats.count
    self.hasDetailLink = detailPathPrefix != nil
    self.detailPathPrefix = detailPathPrefix ?? ""
    self.hasMostRecent = stats.mostRecent != nil
    self.mostRecentID = stats.mostRecent?.id ?? ""
    self.mostRecentName = stats.mostRecent?.name ?? ""
    self.lastUpdatedLabel = stats.lastUpdated.map(formatDateShort) ?? ""
  }
}

func formatDateShort(_ date: Date) -> String {
  let formatter = DateFormatter()
  formatter.dateStyle = .medium
  formatter.timeStyle = .none
  return formatter.string(from: date)
}

struct BrowseContext: Content {
  let query: String
  let noActiveTag: Bool
  let tagCloud: [LeafTag]
  let volumes: [LeafVolumeCard]
  let noResults: Bool
  let user: LeafUser?
  let meta: PageMeta
}

struct DetailContext: Content {
  let volume: LeafVolumeDetail
  /// `true` when the signed-in session's roles include submitter/editor/admin - gates the
  /// "Edit" action. `false` (including for an anonymous visitor) hides it entirely.
  let canEdit: Bool
  /// `true` right after a submitter's edit was stored as a proposed change rather than applied
  /// (the `?proposed=1` redirect query param) - shows a "pending review" banner instead of the
  /// change appearing to silently have no effect.
  let justProposed: Bool
  /// Present only for an editor/admin viewer when at least one submitted version is pending -
  /// nil hides the entire review section, including for a submitter who has no review rights.
  let review: LeafVersionReview?
  /// Field names catalog-api flagged as conflicting on the most recent accept action (via the
  /// `?conflicts=` redirect query param) - the live record changed since the proposal was
  /// submitted, so that field wasn't applied. Empty outside of that redirect.
  let conflicts: [String]
  /// `true` only when `conflicts` is non-empty - Leaf's `#if` treats an empty array as truthy,
  /// so the template branches on this instead of `conflicts` directly (same reason
  /// `LeafVolumeDetail` exposes `hasSystemNames` etc. alongside each array).
  let hasConflicts: Bool
  let user: LeafUser?
  let meta: PageMeta
}

struct VersionHistoryContext: Content {
  let volumeID: String
  let volumeTitle: String
  let versions: [LeafVersionSummary]
  // Leaf's #if(versions) is true for a non-nil array regardless of emptiness, so the
  // "no history" branch was dead code for an empty (but non-nil) versions array - explicit flag
  // instead, matching the volume.hasDescription/.hasStagedCover convention used elsewhere.
  // Stored, not computed - Content's synthesized Encodable conformance only encodes stored
  // properties, so a computed one silently never reaches the Leaf template.
  let hasVersions: Bool
  // Distinguishes "the fetch failed" from "this volume genuinely has no version history" - both
  // used to render as the same empty table, giving no signal that something went wrong.
  let fetchFailed: Bool
  let canRollback: Bool
  let user: LeafUser?
  let meta: PageMeta

  init(
    volumeID: String, volumeTitle: String, versions: [LeafVersionSummary], fetchFailed: Bool,
    canRollback: Bool, user: LeafUser?, meta: PageMeta
  ) {
    self.volumeID = volumeID
    self.volumeTitle = volumeTitle
    self.versions = versions
    self.hasVersions = !versions.isEmpty
    self.fetchFailed = fetchFailed
    self.canRollback = canRollback
    self.user = user
    self.meta = meta
  }
}

struct VersionDetailContext: Content {
  let volumeID: String
  let version: LeafVersionDetail
  let canRollback: Bool
  let user: LeafUser?
  let meta: PageMeta
}

/// One row in a volume's version-history list.
struct LeafVersionSummary: Content {
  let version: Int
  let state: String
  let isLive: Bool
  let submittedBy: String
  let submittedAtLabel: String
  let reviewedBy: String
  let hasReviewedBy: Bool
  let reviewNote: String
  let hasReviewNote: Bool

  init(_ attributes: VolumeVersionAttributes) {
    self.version = attributes.version
    self.state = attributes.state
    self.isLive = attributes.state == "live"
    self.submittedBy = humanizeSubmitterID(attributes.submittedBy)
    self.submittedAtLabel = LeafVersionSummary.format(attributes.submittedAt)
    self.reviewedBy = attributes.reviewedBy.map(humanizeSubmitterID) ?? ""
    self.hasReviewedBy = attributes.reviewedBy != nil
    self.reviewNote = attributes.reviewNote ?? ""
    self.hasReviewNote = attributes.reviewNote != nil
  }

  private static func format(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }
}

/// One version's full field snapshot, for the single-version inspection view.
struct LeafVersionDetail: Content {
  let version: Int
  let state: String
  let isLive: Bool
  let title: String
  let description: String
  let hasDescription: Bool
  let notes: String
  let hasNotes: Bool
  let format: String
  let submittedBy: String
  let submittedAtLabel: String
  let reviewedBy: String
  let hasReviewedBy: Bool
  let reviewNote: String
  let hasReviewNote: Bool

  init(_ attributes: VolumeVersionAttributes) {
    self.version = attributes.version
    self.state = attributes.state
    self.isLive = attributes.state == "live"
    self.title = attributes.title
    self.description = attributes.description
    self.hasDescription = !attributes.description.isEmpty
    self.notes = attributes.notes
    self.hasNotes = !attributes.notes.isEmpty
    self.format = attributes.format
    self.submittedBy = humanizeSubmitterID(attributes.submittedBy)
    self.submittedAtLabel = LeafVersionDetail.format(attributes.submittedAt)
    self.reviewedBy = attributes.reviewedBy.map(humanizeSubmitterID) ?? ""
    self.hasReviewedBy = attributes.reviewedBy != nil
    self.reviewNote = attributes.reviewNote ?? ""
    self.hasReviewNote = attributes.reviewNote != nil
  }

  private static func format(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }
}

struct EditContext: Content {
  let volume: LeafVolumeEditForm
  /// `true` when the signed-in session's roles include editor/admin - gates the cover-upload
  /// control. Every viewer of this page already passed `canEdit` (enforced in `editForm`), but
  /// cover upload is editor/admin-only, same as on the detail page before it moved here.
  let canUploadCover: Bool
  /// Set only when `submitEdit` re-renders this page after a failed finalize (e.g. the
  /// unapproved-submission cap) - shown as an inline banner rather than a generic error page,
  /// task 6.5. `nil` on a normal page load.
  let submitError: String?
  /// A *stored* property, not computed from `submitError` - Swift's synthesized `Encodable`
  /// (which `Content` relies on) only encodes stored properties, so a computed `hasX` here
  /// would silently vanish from what Leaf actually sees and always render as false. Set once,
  /// in the initializer.
  let hasSubmitError: Bool
  let user: LeafUser?
  let meta: PageMeta

  init(
    volume: LeafVolumeEditForm, canUploadCover: Bool, submitError: String?, user: LeafUser?,
    meta: PageMeta
  ) {
    self.volume = volume
    self.canUploadCover = canUploadCover
    self.submitError = submitError
    self.hasSubmitError = submitError != nil
    self.user = user
    self.meta = meta
  }
}

/// Shown instead of the edit form when the caller already has an in-flight session for a
/// *different* volume (task 6.2) - a same-type conflict, distinct from having a session for a
/// different record type, which never triggers this at all.
struct EditSessionConflictContext: Content {
  let volumeID: String
  let volumeTitle: String
  let otherVolumeID: String
  let otherVolumeTitle: String
  /// The other session's staged cover path (`asset/cover-staged/<id>`) - lets the "discard and
  /// edit this instead" action reclaim it client-side before discarding, same as `edit.leaf`'s
  /// own discard handler. Empty when the other session has no staged cover.
  let otherStagedCoverPath: String
  /// A *stored* property (see `EditContext.hasSubmitError`'s comment on why this can't be
  /// computed from `otherStagedCoverPath` and still reach Leaf).
  let hasOtherStagedCover: Bool
  let user: LeafUser?
  let meta: PageMeta

  init(
    volumeID: String, volumeTitle: String, otherVolumeID: String, otherVolumeTitle: String,
    otherStagedCoverPath: String, user: LeafUser?, meta: PageMeta
  ) {
    self.volumeID = volumeID
    self.volumeTitle = volumeTitle
    self.otherVolumeID = otherVolumeID
    self.otherVolumeTitle = otherVolumeTitle
    self.otherStagedCoverPath = otherStagedCoverPath
    self.hasOtherStagedCover = !otherStagedCoverPath.isEmpty
    self.user = user
    self.meta = meta
  }
}

// MARK: - Leaf page contexts

struct EntityBrowseContext<Item: Content>: Content {
  let query: String
  let items: [Item]
  let noResults: Bool
  let orderIsAsc: Bool
  let orderIsDesc: Bool
  let canEdit: Bool
  let user: LeafUser?
  let meta: PageMeta
}

/// One context type covering all four detail pages - only the field matching the page being
/// rendered is non-nil, since each type's template only reads its own field.
struct EntityDetailContext: Content {
  var publisher: LeafPublisherDetail?
  var studio: LeafStudioDetail?
  var person: LeafPersonDetail?
  var license: LeafLicenseDetail?
  let canEdit: Bool
  let justProposed: Bool
  let review: LeafEntityVersionReview?
  let conflicts: [String]
  let user: LeafUser?
  let meta: PageMeta

  init(
    publisher: LeafPublisherDetail? = nil, studio: LeafStudioDetail? = nil,
    person: LeafPersonDetail? = nil, license: LeafLicenseDetail? = nil,
    canEdit: Bool, justProposed: Bool, review: LeafEntityVersionReview?, conflicts: [String],
    user: LeafUser?, meta: PageMeta
  ) {
    self.publisher = publisher
    self.studio = studio
    self.person = person
    self.license = license
    self.canEdit = canEdit
    self.justProposed = justProposed
    self.review = review
    self.conflicts = conflicts
    self.user = user
    self.meta = meta
  }
}

/// Version-model replacement for the old `LeafEntityProposalReview`/`LeafEntityProposalOption` -
/// see `LeafVersionReview` (Editing.swift) for volume's non-generic counterpart. An
/// `EntityVersionAttributes` carries no explicit old/new diff map, so the diff is computed here
/// against the record's current live values via the caller-supplied `versionFieldValues`
/// extractor (needed since Swift generics can't call an overloaded free function generically
/// without it).
struct LeafEntityVersionReview: Content {
  let recordID: String
  let pendingCount: Int
  let hasMultiplePending: Bool
  let options: [LeafEntityVersionOption]
  let selectedVersion: Int
  let submittedBy: String
  let submittedAtLabel: String
  let fields: [LeafEntityFieldDiff]

  init<T: EntityVersionAttributes>(
    recordID: String, currentValues: [String: String], pending: [T], selected: T,
    fieldSpecs: [EntityFieldSpec], versionFieldValues: (T) -> [String: String]
  ) {
    self.recordID = recordID
    self.pendingCount = pending.count
    self.hasMultiplePending = pending.count > 1
    self.options = pending.map { version in
      LeafEntityVersionOption(
        version: version.version,
        submittedBy: humanizeSubmitterID(version.submittedBy),
        submittedAtLabel: Self.format(version.submittedAt),
        isSelected: version.version == selected.version
      )
    }
    self.selectedVersion = selected.version
    self.submittedBy = humanizeSubmitterID(selected.submittedBy)
    self.submittedAtLabel = Self.format(selected.submittedAt)
    let submittedValues = versionFieldValues(selected)
    self.fields = fieldSpecs.compactMap { field in
      let oldValue = currentValues[field.key] ?? ""
      guard let newValue = submittedValues[field.key], oldValue != newValue else { return nil }
      return LeafEntityFieldDiff(
        key: field.key, label: field.label, oldValue: oldValue, newValue: newValue)
    }
  }

  private static func format(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }
}
