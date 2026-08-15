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

struct LeafProposalOption: Content {
  let id: String
  let submittedBy: String
  let submittedAtLabel: String
  let isSelected: Bool
}

struct LeafProposalReview: Content {
  let volumeID: String
  let pendingCount: Int
  let hasMultiplePending: Bool
  let options: [LeafProposalOption]
  let selectedID: String
  let submittedBy: String
  let submittedAtLabel: String
  let fields: [LeafFieldDiff]

  init(volumeID: String, pending: [ProposedChangeSummary], selected: ProposedChangeSummary) {
    self.volumeID = volumeID
    self.pendingCount = pending.count
    self.hasMultiplePending = pending.count > 1
    self.options = pending.map { proposal in
      LeafProposalOption(
        id: proposal.id,
        submittedBy: proposal.submittedBy,
        submittedAtLabel: Self.format(proposal.submittedAt),
        isSelected: proposal.id == selected.id
      )
    }
    self.selectedID = selected.id
    self.submittedBy = selected.submittedBy
    self.submittedAtLabel = Self.format(selected.submittedAt)
    self.fields = patchableFields.compactMap { field in
      guard let change = selected.diff[field.key] else { return nil }
      return LeafFieldDiff(
        key: field.key, label: field.label,
        oldValue: change.old ?? "", newValue: change.new ?? "")
    }
  }

  private static func format(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }
}


/// The volume detail page's fixed, ordered list of fields a `PATCH`/proposal can touch -
/// `ProposedChangeSummary.diff` is a `[String: FieldChange]` dictionary with no defined
/// iteration order, so the diff table and review UI both walk this list instead of the raw
/// dictionary keys, keeping row order stable and matching the edit form's field order.
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

struct LeafEntityFieldInput: Content {
  let key: String
  let label: String
  let value: String
}

struct LeafEntityFieldDiff: Content {
  let key: String
  let label: String
  let oldValue: String
  let newValue: String
}

struct LeafEntityProposalOption: Content {
  let id: String
  let submittedBy: String
  let submittedAtLabel: String
  let isSelected: Bool
}
