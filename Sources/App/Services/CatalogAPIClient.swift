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
      return VolumeViewModel(
        id: resource.id,
        title: resource.attributes.title ?? "Untitled",
        description: resource.attributes.description ?? "",
        notes: resource.attributes.notes ?? "",
        tags: (resource.attributes.tags ?? []).map(\.displayName).filter { !$0.isEmpty },
        systemNames: names("system", from: systemNames),
        publisherNames: names("publisher", from: publisherNames),
        studioNames: names("studio", from: studioNames),
        licenseNames: names("license", from: licenseNames)
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
