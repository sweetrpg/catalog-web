import CatalogAPIClient
import Crypto
import Foundation
import Vapor

struct LeafPersonCard: Content {
  let id: String
  let name: String
  /// Distinct credited-volume count for the browse card badge; 0 renders no badge at all
  /// (catalog-entity-browse), so callers without counts data can omit it.
  let contributionCount: Int
  let contributionCountLabel: String

  init(_ person: PersonViewModel, contributionCount: Int = 0, locale: Locale) {
    self.id = person.id
    self.name = person.name
    self.contributionCount = contributionCount
    self.contributionCountLabel = formatCount(contributionCount, locale: locale)
  }
}

/// The bulk-add-persons page's context (catalog-entity-bulk-add) - editor/admin only.
struct BulkAddPersonsContext: Content {
  let backPath: String
  let submitPath: String
  let user: LeafUser?
  let meta: PageMeta
}

struct LeafBulkAddFailure: Content {
  let name: String
  let error: String
}

/// persons/browse's own context rather than the shared `EntityBrowseContext<Item>` (publishers/
/// studios/licenses also use) - the bulk-add button and its post-submit result banner are
/// Person-only (catalog-entity-bulk-add's scope), so this avoids adding fields the other three
/// controllers would have to pass a constant `false`/empty value for. Otherwise identical to
/// `EntityBrowseContext<LeafPersonCard>`.
struct PersonsBrowseContext: Content {
  let query: String
  let items: [LeafPersonCard]
  let noResults: Bool
  let orderIsAsc: Bool
  let orderIsDesc: Bool
  let canEdit: Bool
  let canBulkAdd: Bool
  /// Set from the bulk-add submit handler's redirect query params - counts plus each failed
  /// entry's name/reason, so the editor sees exactly which lines didn't take (task 3.4).
  let hasBulkResult: Bool
  let bulkCreatedCount: Int
  let bulkCreatedCountLabel: String
  let bulkFailedCount: Int
  let bulkFailedCountLabel: String
  let bulkFailures: [LeafBulkAddFailure]
  let pagination: LeafPagination
  let user: LeafUser?
  let meta: PageMeta

  init(
    query: String,
    items: [LeafPersonCard],
    noResults: Bool,
    orderIsAsc: Bool,
    orderIsDesc: Bool,
    canEdit: Bool,
    canBulkAdd: Bool,
    hasBulkResult: Bool,
    bulkCreatedCount: Int,
    bulkFailedCount: Int,
    bulkFailures: [LeafBulkAddFailure],
    pagination: LeafPagination,
    user: LeafUser?,
    meta: PageMeta,
    locale: Locale
  ) {
    self.query = query
    self.items = items
    self.noResults = noResults
    self.orderIsAsc = orderIsAsc
    self.orderIsDesc = orderIsDesc
    self.canEdit = canEdit
    self.canBulkAdd = canBulkAdd
    self.hasBulkResult = hasBulkResult
    self.bulkCreatedCount = bulkCreatedCount
    self.bulkCreatedCountLabel = formatCount(bulkCreatedCount, locale: locale)
    self.bulkFailedCount = bulkFailedCount
    self.bulkFailedCountLabel = formatCount(bulkFailedCount, locale: locale)
    self.bulkFailures = bulkFailures
    self.pagination = pagination
    self.user = user
    self.meta = meta
  }
}

struct LeafPersonContribution: Content {
  let id: String
  let title: String
  let role: String
}

struct LeafPersonDetail: Content {
  let id: String
  let name: String
  let notes: String
  let hasNotes: Bool
  let tags: [String]
  let contributions: [LeafPersonContribution]
  let hasContributions: Bool

  init(_ person: PersonViewModel) {
    self.id = person.id
    self.name = person.name
    self.notes = person.notes
    self.hasNotes = !person.notes.isEmpty
    self.tags = person.tags
    self.contributions = person.volumes.map { volume in
      LeafPersonContribution(
        id: volume.id, title: volume.title,
        role: person.contributionRoles[volume.id] ?? "Contributor")
    }
    self.hasContributions = !person.volumes.isEmpty
  }
}
