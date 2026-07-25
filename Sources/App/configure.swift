import Leaf
import Redis
import Vapor

// TODO: HEALTH_TOKEN-gated deep health check (see docs/service-conventions.md's Health checks
// section) once this app has something worth deep-checking beyond "is the process up" - right
// now it has no local state (Redis is a cache, not a source of truth), so a shallow liveness
// check is the honest answer.

public func configure(_ app: Application) async throws {
  app.http.server.configuration.hostname = "0.0.0.0"
  app.http.server.configuration.port = Environment.get("PORT").flatMap(Int.init) ?? 8080

  MetricsSetup.bootstrap(app)
  try await TracingSetup.bootstrap(app)
  app.middleware.use(SentryMiddleware())

  app.views.use(.leaf)

  app.sessions.configuration.cookieName = "catalog-web-session"
  // Redis-backed sessions: this app runs multiple replicas (see kubernetes/base/deployment.yaml)
  // behind a Service with no session affinity, so an in-memory session store would only work
  // for whichever replica handled login. Falls back further down if Redis isn't configured.

  if let redisHost = Environment.get("REDIS_HOST"), !redisHost.isEmpty {
    let redisPort = Environment.get("REDIS_PORT").flatMap(Int.init) ?? 6379
    // A separate logical DB index (not just the "catalog:" key prefix in CacheService) from
    // whatever catalog-api uses on the same Redis instance - catalog-api doesn't currently
    // select one explicitly either (its REDIS_DB plumbing is still a TODO there), so relying
    // on prefixes alone as the only isolation would be fragile if that changes.
    let redisDB = Environment.get("REDIS_DB").flatMap(Int.init) ?? 1
    app.redis.configuration = try RedisConfiguration(
      hostname: redisHost,
      port: redisPort,
      password: Environment.get("REDIS_PASS"),
      database: redisDB
    )
    app.redisConfigured = true
    // Not `.redis` (Vapor's stock RedisSessionsDriver): that driver propagates Redis errors
    // straight through SessionsMiddleware, which runs on every request, so a Redis outage would
    // 500 the whole app. ResilientRedisSessionDriver degrades instead - see its doc comment.
    app.sessions.use { _ in ResilientRedisSessionDriver() }
  } else {
    app.logger.warning(
      "REDIS_HOST not set - using in-memory sessions and no response caching. Fine for local development, not for multi-replica deployments."
    )
    app.sessions.use(.memory)
  }
  app.middleware.use(app.sessions.middleware)

  if let corsMiddleware = CORSConfig.middleware() {
    // Inserted at position 0: CORS must run before anything else so preflight OPTIONS
    // requests get a response before hitting auth/session/rate-limit logic that don't
    // apply to them.
    app.middleware.use(corsMiddleware, at: .beginning)
  } else {
    app.logger.warning("ALLOWED_ORIGINS not set, no cross-origin requests will be allowed")
  }

  let rateLimit = Environment.get("RATE_LIMIT").flatMap(Int.init) ?? 20
  app.middleware.use(RateLimitMiddleware(capacity: rateLimit))

  try routes(app)
}
