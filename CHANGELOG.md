
## Unreleased

### Changed
- Migrated to the platform's shared suite-wide login: removed this app's own Auth0
  Authorization Code flow (`AuthController`, `Auth0Config`, `ResilientRedisSessionDriver`, the
  `/login` page) and its unverified local ID-token decode. `auth-web` is now the sole login
  owner; this app only reads the shared session it establishes (read-only Redis connection,
  fails open on any error).

## 0.3.0 - 2026-07-26

### Added
- Reference shared static assets from assets-web (#10)


### Fixed
- Point OTLP tracing endpoint at Tempo, not dead jaeger-collector



## 0.2.0 - 2026-07-25

### Added
- Point nav logo at the SweetRPG root site, not this app's home


### Fixed
- Auth info



## 0.1.3 - 2026-07-25

### Fixed
- Double v prefix in footer version, port Broadsheet's Source Serif 4



## 0.1.2 - 2026-07-25

### Fixed
- Drop erroneous /0 prefix from in-cluster catalog-api URL
- Serve Public/ static assets via FileMiddleware



## 0.1.1 - 2026-07-25

### Fixed
- Path to cache secrets
- Degrade gracefully when Redis is unavailable



## 0.1.0 - 2026-07-25

### Added
- Scaffold Vapor server-rendered frontend for the Catalog domain
- Add Prometheus metrics, JSON logging, tracing, and Sentry reporting


## Unreleased

### Added
- Initial scaffold: Vapor/Leaf server-rendered frontend for the Catalog domain (Home, Browse, Volume Detail, My Shelves), Auth0 login flow, Redis-backed caching and sessions, CORS/rate-limit middleware, Docker image build, and Kubernetes manifests.
