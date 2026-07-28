import Foundation
import Vapor

/// A banner message as returned by admin-api's `GET /banners`. Only the fields this app
/// renders are decoded - admin-api's `models.BannerMessage` has more (id, scope, timestamps)
/// that catalog-web has no use for yet.
struct Banner: Content {
  let severity: String
  let message: String
}

/// Fetches banner messages from admin-api for this app's scopes (`platform`,
/// `service:catalog`, and the current page), with a bounded-TTL cache and fail-open
/// behavior: any error, timeout, or missing `ADMIN_API_URL` yields an empty list rather than
/// surfacing a failure to the page being decorated - matches main-web's `AdminClient` in
/// spirit (naming and behavior), adapted to this app's Vapor/Redis-cache conventions instead
/// of a hand-rolled in-memory cache.
struct AdminClient {
  let client: Client
  let cache: CacheService
  let baseURL: String?
  let logger: Logger

  init(request: Request) {
    self.client = request.client
    self.cache = request.cacheService
    self.baseURL = request.backendConfig.adminAPIURL
    self.logger = request.logger
  }

  /// Returns active banners for the given scopes (e.g. `["platform", "service:catalog",
  /// "page:/browse"]`), most-severe-first as returned by admin-api. Never throws.
  func fetchBanners(scopes: [String]) async -> [Banner] {
    guard let baseURL else { return [] }

    do {
      return try await cache.getOrSet(
        "admin:banners:\(scopes.joined(separator: ","))", ttlSeconds: 90
      ) {
        try await fetch(baseURL: baseURL, scopes: scopes)
      }
    } catch {
      logger.warning("admin-api banner fetch failed, rendering with no banners: \(error)")
      return []
    }
  }

  private func fetch(baseURL: String, scopes: [String]) async throws -> [Banner] {
    let query = scopes.map {
      "scope=\($0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0)"
    }
    .joined(separator: "&")
    // A 2s ClientRequest.timeout bounds both connect and response wait - unlike a
    // Task-cancellation race, this actually aborts a hung connect() at the NIO level rather
    // than merely giving up on awaiting it while the underlying socket operation keeps running
    // in the background for its own (much longer) default timeout.
    let response = try await client.get(URI(string: "\(baseURL)/banners?\(query)")) { req in
      req.timeout = .seconds(2)
    }
    guard response.status == .ok else {
      throw Abort(.badGateway, reason: "admin-api returned \(response.status)")
    }
    let body = response.body.map { Data(buffer: $0) } ?? Data()
    return try JSONDecoder().decode([Banner].self, from: body)
  }
}

extension Request {
  var adminClient: AdminClient { AdminClient(request: self) }
}
