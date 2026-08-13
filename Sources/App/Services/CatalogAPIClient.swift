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
      func ids(_ key: String) -> [String] {
        rel[key]?.data?.ids ?? []
      }
      func names(_ key: String, from map: [String: String]) -> [String] {
        ids(key).compactMap { map[$0] }
      }
      return VolumeViewModel(
        id: resource.id,
        title: resource.attributes.title ?? "Untitled",
        description: resource.attributes.description ?? "",
        notes: resource.attributes.notes ?? "",
        tags: (resource.attributes.tags ?? []).map(\.displayName).filter { !$0.isEmpty },
        systemNames: names("system", from: systemNames),
        publisherNames: names("publisher", from: publisherNames),
        publisherIds: ids("publisher"),
        studioNames: names("studio", from: studioNames),
        studioIds: ids("studio"),
        licenseNames: names("license", from: licenseNames),
        properties: (resource.attributes.properties ?? []).map { ($0.name, $0.value) },
        format: resource.attributes.format ?? "",
        sampleAssetIds: resource.attributes.sampleAssetIds ?? []
      )
    }.sorted { $0.title < $1.title }
  }

  /// Every publisher, sorted by name - the full candidate list the edit page's publisher picker
  /// filters client-side (see design.md's decision: no search endpoint, just filtering the
  /// existing full-collection fetch).
  func fetchPublisherOptions() async throws -> [(id: String, name: String)] {
    let doc = try await getCached("catalog:/publishers") {
      try await sdk.fetchNamed(path: "/publishers")
    }
    return doc.data.map { ($0.id, $0.attributes.displayName) }.sorted { $0.1 < $1.1 }
  }

  /// Every studio, sorted by name - same rationale as `fetchPublisherOptions`.
  func fetchStudioOptions() async throws -> [(id: String, name: String)] {
    let doc = try await getCached("catalog:/studios") { try await sdk.fetchNamed(path: "/studios") }
    return doc.data.map { ($0.id, $0.attributes.displayName) }.sorted { $0.1 < $1.1 }
  }

  func fetchVolume(id: String, allVolumes: [VolumeViewModel]) async -> VolumeViewModel? {
    // Reuses the already-fetched, already-decorated volume list rather than making a
    // second round trip for a single resource - fine at this data size (dozens to low
    // hundreds of volumes); revisit if the catalog grows large enough that fetching every
    // volume up front to find one stops being cheap.
    allVolumes.first { $0.id == id }
  }

  func fetchCredits(volumeID: String) async throws -> [(
    personId: String, role: String, person: String
  )] {
    async let contributionsDoc = getCached("catalog:contributions") {
      try await sdk.fetchContributions()
    }
    async let personNames = fetchPersonNameMap()

    let (doc, persons) = try await (contributionsDoc, personNames)
    return doc.data.compactMap { resource -> (personId: String, role: String, person: String)? in
      guard let volID = resource.relationships?["volume"]?.data?.ids.first,
        volID == volumeID
      else { return nil }
      guard let personID = resource.relationships?["person"]?.data?.ids.first else { return nil }
      let role =
        resource.attributes.role ?? resource.attributes.credit ?? resource.attributes.title
        ?? "Contributor"
      return (personId: personID, role: role, person: persons[personID] ?? "Unknown")
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

  /// Finalizes the caller's in-flight durable edit session for a volume - see
  /// `CatalogController.submitEdit`.
  func finalizeSession(id: String, token: String) async throws -> VolumePatchResult {
    try await sdk.finalizeSession(id: id, token: token)
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

  /// Every person, sorted by name - the contributor dialog's person picker candidate list
  /// (task 8.1), same client-side-filtering rationale as `fetchPublisherOptions`.
  func fetchPersonOptions() async throws -> [(id: String, name: String)] {
    let doc = try await getCached("catalog:persons") { try await sdk.fetchPersons() }
    return doc.data.map { ($0.id, $0.attributes.displayName) }.sorted { $0.1 < $1.1 }
  }

  /// Lists a shared vocabulary's values (contribution-type/property-name/format).
  func fetchVocabulary(type: String, token: String) async throws -> [String] {
    try await sdk.fetchVocabulary(type: type, token: token).values
  }

  /// Adds a new value to a shared vocabulary - editor/admin only, enforced by catalog-api.
  /// Returns the vocabulary's full value list after the add.
  func addVocabularyValue(type: String, value: String, token: String) async throws -> [String] {
    try await sdk.addVocabularyValue(type: type, value: value, token: token).values
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
