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

  // Serves Public/ (css, images, favicon) - never registered before, so every static asset
  // 404'd through the app's own JSON not-found handler instead of being served as a file.
  app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

  // This app's own cache/rate-limit Redis (sweetrpg-catalog) - unrelated to the shared session
  // Redis configured below.
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
  } else {
    app.logger.warning(
      "REDIS_HOST not set - no response caching. Fine for local development, not for multi-replica deployments."
    )
  }

  // The shared "redis" instance in sweetrpg-support (auth-web's session store), read-only from
  // here - not the same instance as this app's own cache Redis above, and not dedicated to any
  // one service. See docs/frontend-conventions.md's "Shared sweetrpg-support Redis instance"
  // section (sweetrpg/platform) for the full DB-index registry. This app never runs its own
  // Auth0 code-exchange or SessionsMiddleware - see SessionUserAccess.swift.
  if let sharedSessionRedisHost = Environment.get("SHARED_SESSION_REDIS_HOST"),
    !sharedSessionRedisHost.isEmpty
  {
    let sharedSessionRedisPort =
      Environment.get("SHARED_SESSION_REDIS_PORT").flatMap(Int.init) ?? 6379
    // Must match auth-web's own DB index - this app reads the exact session keys auth-web
    // writes, not a namespace of its own.
    let sharedSessionRedisDB =
      Environment.get("SHARED_SESSION_REDIS_DB").flatMap(Int.init) ?? 0
    app.redis(.sharedSession).configuration = try RedisConfiguration(
      hostname: sharedSessionRedisHost,
      port: sharedSessionRedisPort,
      password: Environment.get("SHARED_SESSION_REDIS_PASS"),
      database: sharedSessionRedisDB
    )
    app.sharedSessionRedisConfigured = true
  } else {
    app.logger.warning(
      "SHARED_SESSION_REDIS_HOST not set - every visitor will read as logged-out."
    )
  }

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
