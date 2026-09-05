import CatalogAPIClient
import Crypto
import Foundation
import Vapor

/// One entry in a type-to-filter picker's candidate list (publisher/studio today; person in
/// task group 8) - both the full option set (for client-side filtering, task 7.1) and a
/// currently-selected chip use this same shape.
struct LeafNamedOption: Content {
  let id: String
  let name: String
}

/// One asset staged this session (a sample image today) - the raw id (needed by the page's JS to
/// build the full-replace payload) plus its relative display path.
struct LeafStagedAsset: Content {
  let id: String
  let path: String
}

struct LeafFieldDiff: Content {
  let key: String
  let label: String
  let oldValue: String
  let newValue: String
}

struct LeafVersionOption: Content {
  let version: Int
  let submittedBy: String
  let submittedAtLabel: String
  let isSelected: Bool
}

/// Version-model replacement for the old `LeafProposalReview`/`LeafProposalOption` - see
/// design.md's "`proposed_changes` and its Go package are removed once the migration completes".
/// A `VolumeVersionAttributes` carries no explicit old/new diff map, so the diff is computed
/// here against the volume's current live values.
struct LeafVersionReview: Content {
  let volumeID: String
  let pendingCount: Int
  let pendingCountLabel: String
  let hasMultiplePending: Bool
  let options: [LeafVersionOption]
  let selectedVersion: Int
  let submittedBy: String
  let submittedAtLabel: String
  let fields: [LeafFieldDiff]

  init(
    volumeID: String, currentVolume: VolumeViewModel, pending: [VolumeVersionAttributes],
    selected: VolumeVersionAttributes, locale: Locale
  ) {
    self.volumeID = volumeID
    self.pendingCount = pending.count
    self.pendingCountLabel = formatCount(pending.count, locale: locale)
    self.hasMultiplePending = pending.count > 1
    self.options = pending.map { version in
      LeafVersionOption(
        version: version.version,
        submittedBy: version.submittedBy,
        submittedAtLabel: Self.format(version.submittedAt),
        isSelected: version.version == selected.version
      )
    }
    self.selectedVersion = selected.version
    self.submittedBy = selected.submittedBy
    self.submittedAtLabel = Self.format(selected.submittedAt)
    let liveValues: [String: String] = [
      "title": currentVolume.title, "description": currentVolume.description,
      "notes": currentVolume.notes,
    ]
    let submittedValues: [String: String] = [
      "title": selected.title, "description": selected.description, "notes": selected.notes,
    ]
    self.fields = patchableFields.compactMap { field in
      let oldValue = liveValues[field.key] ?? ""
      let newValue = submittedValues[field.key] ?? ""
      guard oldValue != newValue else { return nil }
      return LeafFieldDiff(
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

/// The volume detail page's fixed, ordered list of fields a `PATCH`/submitted version can touch -
/// a version's diff is computed as a field-name-keyed dictionary with no defined iteration
/// order, so the diff table and review UI both walk this list instead of the raw dictionary
/// keys, keeping row order stable and matching the edit form's field order.
private let patchableFields: [(key: String, label: String)] = [
  ("title", "Title"),
  ("description", "Description"),
  ("notes", "Notes"),
]

struct EntityEditContext: Content {
  let id: String
  let backPath: String
  let submitPath: String
  let fields: [LeafEntityFieldInput]
  let user: LeafUser?
  let meta: PageMeta
}

/// `EntityEditContext` plus a volume-association picker - for entity types (studio today; see
/// `LicenseEditContext` for the license variant, which additionally carries free-text tags) whose
/// edit page needs the picker but not license's extra fields. Mirrors `LicenseEditContext`'s
/// volumes-picker fields exactly so `studios/edit.leaf`'s picker markup/script can be a
/// near-identical copy of `licenses/edit.leaf`'s.
struct EntityEditWithVolumesContext: Content {
  let id: String
  let backPath: String
  let submitPath: String
  let fields: [LeafEntityFieldInput]
  /// The volumes picker writes directly to volume records with no review step (see
  /// sweetrpg/catalog-api#220), so it's only shown to a session with review rights - a
  /// submitter still gets the rest of this form.
  let canManageVolumes: Bool
  let selectedVolumes: [LeafNamedOption]
  let volumeOptionsJSON: String
  let user: LeafUser?
  let meta: PageMeta

  init(
    base: EntityEditContext, canManageVolumes: Bool, selectedVolumes: [VolumeSummary],
    allVolumes: [(id: String, title: String)]
  ) {
    self.id = base.id
    self.backPath = base.backPath
    self.submitPath = base.submitPath
    self.fields = base.fields
    self.canManageVolumes = canManageVolumes
    self.selectedVolumes = selectedVolumes.map { LeafNamedOption(id: $0.id, name: $0.title) }
    let options = allVolumes.map { LeafNamedOption(id: $0.id, name: $0.title) }
    self.volumeOptionsJSON =
      (try? JSONEncoder().encode(options)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    self.user = base.user
    self.meta = base.meta
  }
}

struct LeafEntityFieldInput: Content {
  let key: String
  let label: String
  let value: String
  let isTextarea: Bool
  let isSelect: Bool
  let selectOptions: [LeafSelectOption]
}

struct LeafSelectOption: Content {
  let value: String
  let isSelected: Bool
}

struct LeafEntityFieldDiff: Content {
  let key: String
  let label: String
  let oldValue: String
  let newValue: String
}

struct LeafEntityVersionOption: Content {
  let version: Int
  let submittedBy: String
  let submittedAtLabel: String
  let isSelected: Bool
}
