import Foundation
import Vapor

/// Thin wrapper around catalog-api's JSON:API endpoints. Fetches are cached in Redis for a
/// short TTL (see `CacheService`) since these are read-mostly reference lists hit on every page
/// load - mirrors catalog-api's own gin-contrib/cache pattern of caching per-call rather than
/// blanket-caching every response.
struct CatalogAPIClient {
  let client: Client
  let cache: CacheService
  let baseURL: String

  init(request: Request) {
    self.client = request.client
    self.cache = request.cacheService
    self.baseURL = request.backendConfig.catalogAPIURL
  }

  func fetchVolumes() async throws -> [VolumeViewModel] {
    async let volumesDoc = getCached(
      "catalog:volumes", as: JSONAPIDocument<VolumeAttributes>.self, path: "/volumes")
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
    async let contributionsDoc = getCached(
      "catalog:contributions", as: JSONAPIDocument<ContributionAttributes>.self,
      path: "/contributions")
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
    let doc = try await getCached(
      "catalog:reviews", as: JSONAPIDocument<ReviewAttributes>.self, path: "/reviews")
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
    let doc = try await getCached(
      "catalog:\(path)", as: JSONAPIDocument<NamedAttributes>.self, path: path)
    return Dictionary(uniqueKeysWithValues: doc.data.map { ($0.id, $0.attributes.displayName) })
  }

  private func fetchPersonNameMap() async throws -> [String: String] {
    let doc = try await getCached(
      "catalog:persons", as: JSONAPIDocument<PersonAttributes>.self, path: "/persons")
    return Dictionary(uniqueKeysWithValues: doc.data.map { ($0.id, $0.attributes.displayName) })
  }

  private func getCached<T: Codable & Sendable>(_ cacheKey: String, as type: T.Type, path: String)
    async throws -> T
  {
    try await cache.getOrSet(cacheKey, ttlSeconds: 60) {
      let response = try await client.get(URI(string: baseURL + path))
      let body = response.body.map { Data(buffer: $0) } ?? Data()
      // catalog-api has been observed appending a second, unrelated JSON object after a
      // newline when its Redis cache write fails server-side (a leaked error that should
      // have just been logged, not written to the response) - see
      // sweetrpg/catalog-api#121. Decoding only up to the first newline is defensive
      // against that (and matches the workaround the original client-rendered prototype of
      // this UI used), not a statement that this response shape is expected or supported.
      let firstLine =
        body.split(separator: UInt8(ascii: "\n"), maxSplits: 1, omittingEmptySubsequences: true)
        .first ?? body
      return try JSONDecoder().decode(T.self, from: Data(firstLine))
    }
  }
}

extension Request {
  var catalogAPI: CatalogAPIClient { CatalogAPIClient(request: self) }
}
