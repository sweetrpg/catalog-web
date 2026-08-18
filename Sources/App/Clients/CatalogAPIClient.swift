import CatalogAPIClient
import Foundation
import Tracing
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
    try await withSpan("sdk-fetch-volumes") { _ in
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
          publisherIds: ids("publisher"),
          studioNames: names("studio", from: studioNames),
          studioIds: ids("studio"),
          licenseNames: names("license", from: licenseNames),
          properties: (resource.attributes.properties ?? []).map { ($0.name, $0.value) },
          format: resource.attributes.format ?? "",
          sampleAssetIds: resource.attributes.sampleAssetIds ?? [],
          publisherRefs: refs("publisher", from: publisherNames),
          studioRefs: refs("studio", from: studioNames),
          licenseRefs: refs("license", from: licenseNames)
        )
      }.sorted { $0.title < $1.title }
    }
  }

  /// Every publisher, sorted by name - the full candidate list the edit page's publisher picker
  /// filters client-side (see design.md's decision: no search endpoint, just filtering the
  /// existing full-collection fetch).
  func fetchPublisherOptions() async throws -> [(id: String, name: String)] {
    try await withSpan("sdk-fetch-publisher-options") { _ in
      let doc = try await getCached("catalog:/publishers") {
        try await sdk.fetchNamed(path: "/publishers")
      }

      return doc.data.map { ($0.id, $0.attributes.displayName) }.sorted { $0.1 < $1.1 }
    }
  }

  /// Every studio, sorted by name - same rationale as `fetchPublisherOptions`.
  func fetchStudioOptions() async throws -> [(id: String, name: String)] {
    try await withSpan("sdk-fetch-studio-options") { _ in
      let doc = try await getCached("catalog:/studios") {
        try await sdk.fetchNamed(path: "/studios")
      }
      return doc.data.map { ($0.id, $0.attributes.displayName) }.sorted { $0.1 < $1.1 }
    }
  }

  func fetchVolume(id: String, allVolumes: [VolumeViewModel]) async -> VolumeViewModel? {
    withSpan("sdk-fetch-volume") { _ in
      // Reuses the already-fetched, already-decorated volume list rather than making a
      // second round trip for a single resource - fine at this data size (dozens to low
      // hundreds of volumes); revisit if the catalog grows large enough that fetching every
      // volume up front to find one stops being cheap.
      // TODO: dear robot, this is dumb and not forward-looking; a single entity retrieval should
      // never be an expensive operation
      allVolumes.first { $0.id == id }
    }
  }

  func fetchCredits(volumeID: String) async throws -> [(
    personId: String, role: String, person: String
  )] {
    try await withSpan("sdk-fetch-credits") { _ in
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
  }

  func fetchReviews(volumeID: String) async throws -> [(author: String, rating: Int, text: String)]
  {
    try await withSpan("sdk-fetch-reviews") { _ in
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
  }

  /// Edits a volume, or proposes an edit for review - catalog-api decides which based on the
  /// bearer token's verified roles. This app does no role logic of its own for the write
  /// itself, only for which UI to show (see `CatalogController.editForm`/`submitEdit`).
  func patchVolume(
    id: String, token: String, title: String?, description: String?, notes: String?
  ) async throws -> VolumePatchResult {
    try await withSpan("sdk-patch-volume") { _ in
      try await sdk.patchVolume(
        id: id, token: token, title: title, description: description, notes: notes)
    }
  }

  /// Finalizes the caller's in-flight durable edit session for a volume - see
  /// `CatalogController.submitEdit`.
  func finalizeSession(id: String, token: String) async throws -> VolumePatchResult {
    try await withSpan("sdk-finalize-session") { _ in
      try await sdk.finalizeSession(id: id, token: token)
    }
  }

  /// Accepts a submitted volume version in full (`fields: nil`) or in part. Editor/admin only,
  /// enforced by catalog-api.
  func acceptVolumeVersion(
    volumeID: String, version: Int, token: String, fields: [String]?
  ) async throws -> ReviewVersionResult {
    try await withSpan("sdk-accept-volume-version") { _ in
      try await sdk.acceptVolumeVersion(
        id: volumeID, version: version, token: token, fields: fields)
    }
  }

  /// Rejects a submitted volume version in full, with an optional review note. Editor/admin
  /// only, enforced by catalog-api.
  func rejectVolumeVersion(
    volumeID: String, version: Int, token: String, note: String?
  ) async throws -> ReviewVersionResult {
    try await withSpan("sdk-reject-volume-version") { _ in
      try await sdk.rejectVolumeVersion(id: volumeID, version: version, token: token, note: note)
    }
  }

  /// Lists a volume's version history, newest first.
  func fetchVolumeVersions(volumeID: String, token: String) async throws
    -> [VolumeVersionAttributes]
  {
    try await withSpan("sdk-fetch-volume-versions") { _ in
      try await sdk.fetchVolumeVersions(id: volumeID, token: token)
    }
  }

  /// Fetches one version's full field snapshot, regardless of whether it's current.
  func fetchVolumeVersion(volumeID: String, version: Int, token: String) async throws
    -> VolumeVersionAttributes
  {
    try await withSpan("sdk-fetch-volume-version") { _ in
      try await sdk.fetchVolumeVersion(id: volumeID, version: version, token: token)
    }
  }

  /// Rolls a volume back (or forward) to an arbitrary existing version - admin only, enforced by
  /// catalog-api.
  func setCurrentVolumeVersion(volumeID: String, version: Int, token: String) async throws
    -> VolumeVersionAttributes
  {
    try await withSpan("sdk-set-current-volume-version") { _ in
      try await sdk.setCurrentVolumeVersion(id: volumeID, version: version, token: token)
    }
  }

  /// Every person, sorted by name - the contributor dialog's person picker candidate list
  /// (task 8.1), same client-side-filtering rationale as `fetchPublisherOptions`.
  func fetchPersonOptions() async throws -> [(id: String, name: String)] {
    try await withSpan("sdk-fetch-persons") { _ in
      let doc = try await getCached("catalog:persons") { try await sdk.fetchPersons() }
      return doc.data.map { ($0.id, $0.attributes.displayName) }.sorted { $0.1 < $1.1 }
    }
  }

  /// Lists a shared vocabulary's values (contribution-type/property-name/format).
  func fetchVocabulary(type: String, token: String) async throws -> [String] {
    try await withSpan("sdk-fetch-vocabulary") { _ in
      try await sdk.fetchVocabulary(type: type, token: token).values
    }
  }

  /// Adds a new value to a shared vocabulary - editor/admin only, enforced by catalog-api.
  /// Returns the vocabulary's full value list after the add.
  func addVocabularyValue(type: String, value: String, token: String) async throws -> [String] {
    try await withSpan("sdk-add-vocabulary-value") { _ in
      try await sdk.addVocabularyValue(type: type, value: value, token: token).values
    }
  }

  func fetchPublishers() async throws -> [PublisherViewModel] {
    try await withSpan("sdk-fetch-publishers") { _ in
      let doc = try await getCached("catalog:publishers") { try await sdk.fetchPublishers() }
      return doc.data.map { PublisherViewModel(id: $0.id, attributes: $0.attributes) }
        .sorted { $0.name < $1.name }
    }
  }

  func fetchPublisher(id: String) async throws -> PublisherViewModel? {
    try await withSpan("sdk-fetch-publisher") { _ in
      let doc = try await sdk.fetchPublisher(id: id)
      return PublisherViewModel(id: doc.data.id, attributes: doc.data.attributes)
    }
  }

  func fetchPublisherVolumes(id: String) async throws -> [VolumeSummary] {
    try await withSpan("sdk-fetch-publisher-volumes") { _ in
      let doc = try await sdk.fetchPublisherVolumes(id: id)
      return doc.data.map { VolumeSummary(id: $0.id, title: $0.attributes.title ?? "Untitled") }
    }
  }

  func fetchStudios() async throws -> [StudioViewModel] {
    try await withSpan("sdk-fetch-studios") { _ in
      let doc = try await getCached("catalog:studios") { try await sdk.fetchStudios() }
      return doc.data.map { StudioViewModel(id: $0.id, attributes: $0.attributes) }
        .sorted { $0.name < $1.name }
    }
  }

  func fetchStudio(id: String) async throws -> StudioViewModel? {
    try await withSpan("sdk-fetch-studio") { _ in
      let doc = try await sdk.fetchStudio(id: id)
      return StudioViewModel(id: doc.data.id, attributes: doc.data.attributes)
    }
  }

  func fetchStudioVolumes(id: String) async throws -> [VolumeSummary] {
    try await withSpan("sdk-fetch-studio-volumes") { _ in
      let doc = try await sdk.fetchStudioVolumes(id: id)
      return doc.data.map { VolumeSummary(id: $0.id, title: $0.attributes.title ?? "Untitled") }
    }
  }

  func fetchPersonsCatalog() async throws -> [PersonViewModel] {
    try await withSpan("sdk-fetch-persons-catalog") { _ in
      let doc = try await getCached("catalog:persons-list") { try await sdk.fetchPersons() }
      return doc.data.map { PersonViewModel(id: $0.id, attributes: $0.attributes) }
        .sorted { $0.name < $1.name }
    }
  }

  func fetchPerson(id: String) async throws -> PersonViewModel? {
    try await withSpan("sdk-fetch-person") { _ in
      let doc = try await sdk.fetchPerson(id: id)
      return PersonViewModel(id: doc.data.id, attributes: doc.data.attributes)
    }
  }

  func fetchPersonVolumes(id: String) async throws -> [VolumeSummary] {
    try await withSpan("sdk-fetch-person-volumes") { _ in
      let doc = try await sdk.fetchPersonVolumes(id: id)
      return doc.data.map { VolumeSummary(id: $0.id, title: $0.attributes.title ?? "Untitled") }
    }
  }

  func fetchLicenses() async throws -> [LicenseViewModel] {
    try await withSpan("sdk-fetch-licenses") { _ in
      let doc = try await getCached("catalog:licenses-list") { try await sdk.fetchLicenses() }
      return doc.data.map { LicenseViewModel(id: $0.id, attributes: $0.attributes) }
        .sorted { $0.title < $1.title }
    }
  }

  func fetchLicense(id: String) async throws -> LicenseViewModel? {
    try await withSpan("sdk-fetch-license") { _ in
      let doc = try await sdk.fetchLicense(id: id)
      return LicenseViewModel(id: doc.data.id, attributes: doc.data.attributes)
    }
  }

  func fetchLicenseVolumes(id: String) async throws -> [VolumeSummary] {
    try await withSpan("sdk-fetch-license-volumes") { _ in
      let doc = try await sdk.fetchLicenseVolumes(id: id)
      return doc.data.map { VolumeSummary(id: $0.id, title: $0.attributes.title ?? "Untitled") }
    }
  }

  /// Outcome of a generic entity PATCH - the applied document's contents aren't used by any
  /// caller (the controller just redirects), so this discards them rather than threading a
  /// per-type `Attributes` generic parameter up through the controller layer.
  enum PatchOutcome {
    case applied
    case proposed(SubmittedVersionResponse)
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

  /// Lists a publisher/studio/person/license's version history, newest first - the generic
  /// counterpart of `fetchVolumeVersions(volumeID:token:)`.
  func fetchEntityVersions<T: EntityVersionAttributes>(path: String, id: String, token: String)
    async throws -> [T]
  {
    try await withSpan("sdk-fetch-entity-versions") { _ in
      try await sdk.fetchEntityVersions(path: path, id: id, token: token)
    }
  }

  /// Accepts a publisher/studio/person/license submitted version, in full or in part - the
  /// generic counterpart of `acceptVolumeVersion`. Editor/admin only, enforced by catalog-api.
  func acceptEntityVersion(
    path: String, id: String, version: Int, token: String, fields: [String]?
  ) async throws -> ReviewVersionResult {
    try await withSpan("sdk-accept-entity-version") { _ in
      try await sdk.acceptEntityVersion(
        path: path, id: id, version: version, token: token, fields: fields)
    }
  }

  /// Rejects a publisher/studio/person/license submitted version - the generic counterpart of
  /// `rejectVolumeVersion`. Editor/admin only, enforced by catalog-api.
  func rejectEntityVersion(
    path: String, id: String, version: Int, token: String, note: String?
  ) async throws -> ReviewVersionResult {
    try await withSpan("sdk-reject-entity-version") { _ in
      try await sdk.rejectEntityVersion(
        path: path, id: id, version: version, token: token, note: note)
    }
  }

  private func fetchNameMap(path: String) async throws -> [String: String] {
    try await withSpan("sdk-fetch-named") { _ in
      let doc = try await getCached("catalog:\(path)") { try await sdk.fetchNamed(path: path) }
      return Dictionary(uniqueKeysWithValues: doc.data.map { ($0.id, $0.attributes.displayName) })
    }
  }

  private func fetchPersonNameMap() async throws -> [String: String] {
    try await withSpan("sdk-fetch-persons") { _ in
      let doc = try await getCached("catalog:persons") { try await sdk.fetchPersons() }
      return Dictionary(uniqueKeysWithValues: doc.data.map { ($0.id, $0.attributes.displayName) })
    }
  }

  private func getCached<T: Codable & Sendable>(
    _ cacheKey: String, fetch: @Sendable () async throws -> T
  ) async throws -> T {
    try await withSpan("sdk-cache-get-or-set") { _ in
      try await cache.getOrSet(cacheKey, ttlSeconds: 60, fetch: fetch)
    }
  }
}

extension Request {
  var catalogAPI: CatalogAPIClientService { CatalogAPIClientService(request: self) }
}
