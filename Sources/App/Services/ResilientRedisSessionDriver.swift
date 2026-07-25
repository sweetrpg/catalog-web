import Redis
import Vapor

/// Redis-backed session driver that degrades instead of failing the request when Redis is
/// unreachable. Vapor's stock `RedisSessionsDriver` (used via `app.sessions.use(.redis)`)
/// propagates any Redis error straight through `SessionsMiddleware`, which runs on every
/// request - so a Redis outage would 500 the whole app, not just the caching path that
/// `CacheService` already degrades gracefully.
///
/// Reads fail open to "no session" (the request proceeds as logged-out); writes and deletes are
/// logged and swallowed so the response still succeeds, at the cost of the session not
/// surviving until Redis recovers.
struct ResilientRedisSessionDriver: AsyncSessionDriver {
  private func key(for id: SessionID) -> RedisKey { RedisKey("vrs-\(id.string)") }

  private func makeID() -> SessionID {
    SessionID(string: [UInt8].random(count: 32).base64String())
  }

  func createSession(_ data: SessionData, for request: Request) async throws -> SessionID {
    let id = makeID()
    do {
      try await request.redis.set(key(for: id), toJSON: data).get()
    } catch {
      request.logger.warning("Redis unavailable, session will not persist: \(error)")
    }
    return id
  }

  func readSession(_ sessionID: SessionID, for request: Request) async throws -> SessionData? {
    do {
      return try await request.redis.get(key(for: sessionID), asJSON: SessionData.self).get()
    } catch {
      request.logger.warning("Redis unavailable, treating request as logged-out: \(error)")
      return nil
    }
  }

  func updateSession(
    _ sessionID: SessionID, to data: SessionData, for request: Request
  ) async throws -> SessionID {
    do {
      try await request.redis.set(key(for: sessionID), toJSON: data).get()
    } catch {
      request.logger.warning("Redis unavailable, session update dropped: \(error)")
    }
    return sessionID
  }

  func deleteSession(_ sessionID: SessionID, for request: Request) async throws {
    do {
      _ = try await request.redis.delete(key(for: sessionID)).get()
    } catch {
      request.logger.warning("Redis unavailable, session delete dropped: \(error)")
    }
  }
}
