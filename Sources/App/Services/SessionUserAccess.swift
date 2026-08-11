import Redis
import Vapor

/// The shared session cookie `auth-web` writes and every other frontend reads - see design.md's
/// "One shared cookie" decision in platform's add-user-api-authn-authz change.
let sharedSessionCookieName = "sweetrpg_session"

/// Names the Redis connection this app reads the shared session from - a distinct connection
/// from the default `app.redis` (this app's own cache/rate-limit Redis in `sweetrpg-catalog`),
/// pointed instead at `auth-web`'s dedicated Redis instance in `sweetrpg-support`. See
/// `configure.swift`.
extension RedisID {
  static let sharedSession = RedisID("sharedSession")
}

extension Request {
  /// Reads (never writes) the session `auth-web` established for this visitor, if any. Fails
  /// open on every error path (disabled, unreachable Redis, missing cookie, missing key,
  /// malformed JSON) by returning `nil` - the same fail-open contract
  /// `ResilientRedisSessionDriver` gave every Vapor frontend before this app's own copy of it
  /// was removed in favor of this read-only client. This intentionally does NOT go through
  /// Vapor's `Session`/`SessionsMiddleware` machinery: touching `req.session` on every request
  /// would create and write back a brand-new session for every anonymous visitor, which is
  /// exactly the write this read-only consumer must never make.
  var currentUser: SessionUser? {
    get async {
      guard application.sharedSessionRedisConfigured else { return nil }
      guard let sessionID = cookies[sharedSessionCookieName]?.string else { return nil }

      // Key format matches Vapor's ResilientRedisSessionDriver (auth-web's session writer):
      // `vrs-<sessionID>`, JSON-encoded Vapor `SessionData` (a flat `[String: String]`).
      let key = RedisKey("vrs-\(sessionID)")
      guard
        let sessionData = try? await redis(.sharedSession).get(key, asJSON: [String: String].self)
          .get(),
        let userJSON = sessionData["user"],
        let data = userJSON.data(using: .utf8),
        let user = try? JSONDecoder().decode(SessionUser.self, from: data),
        user.expiry > Date()
      else { return nil }

      return user
    }
  }
}
