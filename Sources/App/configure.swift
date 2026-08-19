import Leaf
import LingoVapor
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

  // Creates a server-kind span per request, extracting an inbound traceparent header if present.
  // request.serviceContext is set for the request's duration, so outgoing calls via
  // request.client (AsyncHTTPClient) and CatalogAPIClient (which injects it manually, since it
  // uses URLSession, not AsyncHTTPClient) both link into the resulting trace.
  app.middleware.use(TracingMiddleware())

  app.middleware.use(SentryMiddleware())

  app.views.use(.leaf)

  // Vapor's default (16kb) is well under a full license edit submission - the form posts every
  // field together, including deed/legal_code, and a real license's full legal text alone can
  // run well past 16kb. Raised to 1mb, generous headroom over any legal text this app has seen
  // while still bounding the worst case.
  app.routes.defaultMaxBodySize = "1mb"

  // English only for now (this app's first consumer, no prior platform pattern to extend) -
  // real CLDR-style plural rules via Resources/Localizations/*.json, not hand-rolled
  // "append an s" string logic. Add a locale by dropping another <code>.json file in that
  // directory; request.locale (once a route reads it) picks the right one automatically.
  app.lingoVapor.configuration = .init(
    defaultLocale: "en", localizationsDir: "Resources/Localizations")

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

  // auth-web's own dedicated Redis instance, read-only from here - the shared session store
  // every frontend reads. Not the same instance as this app's own cache Redis above. This app
  // never runs its own Auth0 code-exchange or SessionsMiddleware - see SessionUserAccess.swift.
  if let sharedSessionRedisHost = Environment.get("SHARED_SESSION_REDIS_HOST"),
    !sharedSessionRedisHost.isEmpty
  {
    let sharedSessionRedisPort =
      Environment.get("SHARED_SESSION_REDIS_PORT").flatMap(Int.init) ?? 6379
    // Must match auth-web's own REDIS_DB (DB 2 in every deployed environment) - auth-web is
    // the sole writer of this store, so reading from the wrong DB index silently degrades to
    // "every visitor reads as logged-out" the same way an unreachable host does.
    let sharedSessionRedisDB = Environment.get("SHARED_SESSION_REDIS_DB").flatMap(Int.init) ?? 2
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

  // catalog-api's own Redis instance, DB 2 - the durable volume-edit session store this app
  // both writes (starting/updating a session) and, indirectly via catalog-api's finalize-session
  // endpoint, has read at commit time. Same shape as SHARED_SESSION_REDIS_* above but a
  // different instance/DB: see docs/frontend-conventions.md's edit-session schema and Redis
  // registry in sweetrpg/platform.
  if let editSessionRedisHost = Environment.get("EDIT_SESSION_REDIS_HOST"),
    !editSessionRedisHost.isEmpty
  {
    let editSessionRedisPort =
      Environment.get("EDIT_SESSION_REDIS_PORT").flatMap(Int.init) ?? 6379
    let editSessionRedisDB = Environment.get("EDIT_SESSION_REDIS_DB").flatMap(Int.init) ?? 2
    app.redis(.editSession).configuration = try RedisConfiguration(
      hostname: editSessionRedisHost,
      port: editSessionRedisPort,
      password: Environment.get("EDIT_SESSION_REDIS_PASS"),
      database: editSessionRedisDB
    )
    app.editSessionRedisConfigured = true
  } else {
    app.logger.warning(
      "EDIT_SESSION_REDIS_HOST not set - volume edit sessions will not persist across requests."
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

  // Checked after rate limiting (a request that shouldn't be served at all needn't consume a
  // rate-limit token) but before route dispatch, so an active maintenance window intercepts
  // every route uniformly instead of each controller needing its own check.
  app.middleware.use(MaintenanceModeMiddleware())

  try routes(app)
}
