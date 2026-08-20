import CatalogAPIClient
import Crypto
import Foundation
import Vapor

struct LeafPersonCard: Content {
  let id: String
  let name: String

  init(_ person: PersonViewModel) {
    self.id = person.id
    self.name = person.name
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
  let bulkFailedCount: Int
  let bulkFailures: [LeafBulkAddFailure]
  let user: LeafUser?
  let meta: PageMeta
}

struct LeafPersonDetail: Content {
  let id: String
  let name: String
  let notes: String
  let hasNotes: Bool
  let tags: [String]
  let volumes: [LeafVolumeSummary]
  let hasVolumes: Bool

  init(_ person: PersonViewModel) {
    self.id = person.id
    self.name = person.name
    self.notes = person.notes
    self.hasNotes = !person.notes.isEmpty
    self.tags = person.tags
    self.volumes = person.volumes.map(LeafVolumeSummary.init)
    self.hasVolumes = !person.volumes.isEmpty
  }
}
