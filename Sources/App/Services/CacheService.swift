import Redis
import Vapor

/// Generic get-or-set cache over Vapor's Redis client. Falls through to calling `fetch` directly
/// (no caching) if Redis isn't configured - see `configure.swift` - so caching is an optimization,
/// not a hard dependency for local development or a degraded environment.
struct CacheService {
  let request: Request

  func getOrSet<T: Codable & Sendable>(
    _ key: String, ttlSeconds: Int, fetch: @Sendable () async throws -> T
  ) async throws -> T {
    guard request.application.redisConfigured else {
      return try await fetch()
    }

    if let cached = try? await request.redis.get(RedisKey(key), asJSON: T.self).get() {
      return cached
    }

    let value = try await fetch()
    try? await request.redis.setex(
      RedisKey(key), toJSON: value, expirationInSeconds: ttlSeconds
    ).get()
    return value
  }
}

extension Request {
  var cacheService: CacheService { CacheService(request: self) }
}

extension Application {
  private struct RedisConfiguredKey: StorageKey {
    typealias Value = Bool
  }

  var redisConfigured: Bool {
    get { storage[RedisConfiguredKey.self] ?? false }
    set { storage[RedisConfiguredKey.self] = newValue }
  }
}
