import CatalogAPIClient
import Foundation
import Vapor

/// Thin wrapper around the `catalog-api-client.swift` SDK: assembles this app's decorated
/// `VolumeViewModel`s from the SDK's raw JSON:API fetches, and adds this app's own Redis
/// response caching (see `CacheService`) - the SDK deliberately has none, since caching backend
/// and TTL policy are a per-app decision, not part of the SDK's contract. Named
/// `CatalogAPIClientService` (not `CatalogAPIClient`) to avoid shadowing the imported SDK
/// module of the same name within this file.
struct CatalogAPIClientService {
  let sdk: CatalogAPIClient
  let cache: CacheService

  init(request: Request) {
    self.sdk = CatalogAPIClient(baseURL: request.backendConfig.catalogAPIURL)
    self.cache = request.cacheService
  }

  func fetchVolumes() async throws -> [VolumeViewModel] {
    async let volumesDoc = getCached("catalog:volumes") { try await sdk.fetchVolumes() }
    async let systems = fetchNameMap(path: "/systems")
    async let publishers = fetchNameMap(path: "/publishers")
    async let studios = fetchNameMap(path: "/studios")
    async let licenses = fetchNameMap(path: "/licenses")

    let (doc, systemNames, publisherNames, studioNames, licenseNames) =
      try await (volumesDoc, systems, publishers, studios, licenses)

    return doc.data.map { resource in
      let rel = resource.relationships ?? [:]
      func names(_ key: String, from map: [String: String]) -> [String] {
        (rel[key]?.data?.ids ?? []).compactMap { map[$0] }
      }
      func refs(_ key: String, from map: [String: String]) -> [EntityRef] {
        (rel[key]?.data?.ids ?? []).compactMap { id in
          map[id].map { EntityRef(id: id, name: $0) }
        }
      }
      return VolumeViewModel(
        id: resource.id,
        title: resource.attributes.title ?? "Untitled",
        description: resource.attributes.description ?? "",
        notes: resource.attributes.notes ?? "",
        tags: (resource.attributes.tags ?? []).map(\.displayName).filter { !$0.isEmpty },
        systemNames: names("system", from: systemNames),
        publisherNames: names("publisher", from: publisherNames),
        studioNames: names("studio", from: studioNames),
        licenseNames: names("license", from: licenseNames),
        publisherRefs: refs("publisher", from: publisherNames),
        studioRefs: refs("studio", from: studioNames),
        licenseRefs: refs("license", from: licenseNames)
      )
    }.sorted { $0.title < $1.title }
  }

  func fetchVolume(id: String, allVolumes: [VolumeViewModel]) async -> VolumeViewModel? {
    // Reuses the already-fetched, already-decorated volume list rather than making a
    // second round trip for a single resource - fine at this data size (dozens to low
    // hundreds of volumes); revisit if the catalog grows large enough that fetching every
    // volume up front to find one stops being cheap.
    allVolumes.first { $0.id == id }
  }

  func fetchCredits(volumeID: String) async throws -> [(role: String, person: String)] {
    async let contributionsDoc = getCached("catalog:contributions") {
      try await sdk.fetchContributions()
    }
    async let personNames = fetchPersonNameMap()

    let (doc, persons) = try await (contributionsDoc, personNames)
    return doc.data.compactMap { resource -> (role: String, person: String)? in
      guard let volID = resource.relationships?["volume"]?.data?.ids.first,
        volID == volumeID
      else { return nil }
      let personID = resource.relationships?["person"]?.data?.ids.first
      let role =
        resource.attributes.role ?? resource.attributes.credit ?? resource.attributes.title
        ?? "Contributor"
      return (role: role, person: personID.flatMap { persons[$0] } ?? "Unknown")
    }
  }

  func fetchReviews(volumeID: String) async throws -> [(author: String, rating: Int, text: String)]
  {
    let doc = try await getCached("catalog:reviews") { try await sdk.fetchReviews() }
    return doc.data.compactMap { resource in
      guard let volID = resource.relationships?["volume"]?.data?.ids.first,
        volID == volumeID
      else { return nil }
      return (
        author: resource.attributes.displayAuthor,
        rating: Int(resource.attributes.displayRating.rounded()),
        text: resource.attributes.displayText
      )
    }
  }

  /// Edits a volume, or proposes an edit for review - catalog-api decides which based on the
  /// bearer token's verified roles. This app does no role logic of its own for the write
  /// itself, only for which UI to show (see `CatalogController.editForm`/`submitEdit`).
  func patchVolume(
    id: String, token: String, title: String?, description: String?, notes: String?
  ) async throws -> VolumePatchResult {
    try await sdk.patchVolume(
      id: id, token: token, title: title, description: description, notes: notes)
  }

  func listProposedChanges(volumeID: String, token: String) async throws
    -> [ProposedChangeSummary]
  {
    try await sdk.listProposedChanges(volumeID: volumeID, token: token)
  }

  func acceptProposedChange(
    volumeID: String, proposalID: String, token: String, fields: [String]?
  ) async throws -> ReviewProposalResult {
    try await sdk.acceptProposedChange(
      volumeID: volumeID, proposalID: proposalID, token: token, fields: fields)
  }

  func rejectProposedChange(
    volumeID: String, proposalID: String, token: String, note: String?
  ) async throws -> ReviewProposalResult {
    try await sdk.rejectProposedChange(
      volumeID: volumeID, proposalID: proposalID, token: token, note: note)
  }

  func fetchPublishers() async throws -> [PublisherViewModel] {
    let doc = try await getCached("catalog:publishers") { try await sdk.fetchPublishers() }
    return doc.data.map { PublisherViewModel(id: $0.id, attributes: $0.attributes) }
      .sorted { $0.name < $1.name }
  }

  func fetchPublisher(id: String) async throws -> PublisherViewModel? {
    let doc = try await sdk.fetchPublisher(id: id)
    return PublisherViewModel(id: doc.data.id, attributes: doc.data.attributes)
  }

  func fetchPublisherVolumes(id: String) async throws -> [VolumeSummary] {
    let doc = try await sdk.fetchPublisherVolumes(id: id)
    return doc.data.map { VolumeSummary(id: $0.id, title: $0.attributes.title ?? "Untitled") }
  }

  func fetchStudios() async throws -> [StudioViewModel] {
    let doc = try await getCached("catalog:studios") { try await sdk.fetchStudios() }
    return doc.data.map { StudioViewModel(id: $0.id, attributes: $0.attributes) }
      .sorted { $0.name < $1.name }
  }

  func fetchStudio(id: String) async throws -> StudioViewModel? {
    let doc = try await sdk.fetchStudio(id: id)
    return StudioViewModel(id: doc.data.id, attributes: doc.data.attributes)
  }

  func fetchStudioVolumes(id: String) async throws -> [VolumeSummary] {
    let doc = try await sdk.fetchStudioVolumes(id: id)
    return doc.data.map { VolumeSummary(id: $0.id, title: $0.attributes.title ?? "Untitled") }
  }

  func fetchPersonsCatalog() async throws -> [PersonViewModel] {
    let doc = try await getCached("catalog:persons-list") { try await sdk.fetchPersons() }
    return doc.data.map { PersonViewModel(id: $0.id, attributes: $0.attributes) }
      .sorted { $0.name < $1.name }
  }

  func fetchPerson(id: String) async throws -> PersonViewModel? {
    let doc = try await sdk.fetchPerson(id: id)
    return PersonViewModel(id: doc.data.id, attributes: doc.data.attributes)
  }

  func fetchPersonVolumes(id: String) async throws -> [VolumeSummary] {
    let doc = try await sdk.fetchPersonVolumes(id: id)
    return doc.data.map { VolumeSummary(id: $0.id, title: $0.attributes.title ?? "Untitled") }
  }

  func fetchLicenses() async throws -> [LicenseViewModel] {
    let doc = try await getCached("catalog:licenses-list") { try await sdk.fetchLicenses() }
    return doc.data.map { LicenseViewModel(id: $0.id, attributes: $0.attributes) }
      .sorted { $0.title < $1.title }
  }

  func fetchLicense(id: String) async throws -> LicenseViewModel? {
    let doc = try await sdk.fetchLicense(id: id)
    return LicenseViewModel(id: doc.data.id, attributes: doc.data.attributes)
  }

  func fetchLicenseVolumes(id: String) async throws -> [VolumeSummary] {
    let doc = try await sdk.fetchLicenseVolumes(id: id)
    return doc.data.map { VolumeSummary(id: $0.id, title: $0.attributes.title ?? "Untitled") }
  }

  /// Outcome of a generic entity PATCH - the applied document's contents aren't used by any
  /// caller (the controller just redirects), so this discards them rather than threading a
  /// per-type `Attributes` generic parameter up through the controller layer.
  enum PatchOutcome {
    case applied
    case proposed(ProposedChangeSubmission)
  }

  /// Edits a publisher/studio/person/license, or proposes an edit for review - the generic
  /// counterpart of `patchVolume`. `path` is the resource's collection path (e.g.
  /// `/publishers`). Decodes the applied-case response as `NamedAttributes` regardless of the
  /// real entity type purely to satisfy the SDK call's generic parameter - its fields
  /// (`name`/`title`, both optional) decode successfully against any of the four types' actual
  /// response shapes without needing to match them, since the decoded value itself is unused.
  func patchEntity(path: String, id: String, token: String, fields: [String: String])
    async throws -> PatchOutcome
  {
    let result: EntityPatchResult<NamedAttributes> = try await sdk.patchEntity(
      path: path, id: id, token: token, fields: fields)
    switch result {
    case .applied: return .applied
    case .proposed(let submission): return .proposed(submission)
    }
  }

  func listProposedChanges(path: String, id: String, token: String) async throws
    -> [ProposedChangeSummary]
  {
    try await sdk.listProposedChanges(path: path, id: id, token: token)
  }

  func acceptProposedChange(
    path: String, id: String, proposalID: String, token: String, fields: [String]?
  ) async throws -> ReviewProposalResult {
    try await sdk.acceptProposedChange(
      path: path, id: id, proposalID: proposalID, token: token, fields: fields)
  }

  func rejectProposedChange(
    path: String, id: String, proposalID: String, token: String, note: String?
  ) async throws -> ReviewProposalResult {
    try await sdk.rejectProposedChange(
      path: path, id: id, proposalID: proposalID, token: token, note: note)
  }

  private func fetchNameMap(path: String) async throws -> [String: String] {
    let doc = try await getCached("catalog:\(path)") { try await sdk.fetchNamed(path: path) }
    return Dictionary(uniqueKeysWithValues: doc.data.map { ($0.id, $0.attributes.displayName) })
  }

  private func fetchPersonNameMap() async throws -> [String: String] {
    let doc = try await getCached("catalog:persons") { try await sdk.fetchPersons() }
    return Dictionary(uniqueKeysWithValues: doc.data.map { ($0.id, $0.attributes.displayName) })
  }

  private func getCached<T: Codable & Sendable>(
    _ cacheKey: String, fetch: @Sendable () async throws -> T
  ) async throws -> T {
    try await cache.getOrSet(cacheKey, ttlSeconds: 60, fetch: fetch)
  }
}

extension Request {
  var catalogAPI: CatalogAPIClientService { CatalogAPIClientService(request: self) }
}
