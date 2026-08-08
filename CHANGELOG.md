
## 0.7.0 - 2026-08-08

### Added
- Render a Gravatar image in the avatar circle



## 0.6.0 - 2026-08-05

### Added
- Swap nav logo for theme-aware SVGs


### Fixed
- Respect the shared dark theme
- Bump builder image to swift:6.2-jammy



## 0.5.0 - 2026-08-04

### Added
- Adopt admin-api-client.swift for maintenance mode
- Replace plain-text user identity with the shared avatar menu


### Changed
- Adopt catalog-api-client.swift SDK, drop in-tree JSON:API client


### Fixed
- Await the EventLoopFuture from encodeResponse correctly
- Authenticate to the shared session Redis



## 0.4.3 - 2026-08-01


## 0.4.2 - 2026-08-01

### Fixed
- Drop dead COPY of removed Public/ directory (#33)



## 0.4.1 - 2026-08-01

### Fixed
- Point shared session Redis at the correct host/DB (#31)



## 0.4.0 - 2026-08-01

### Added
- Add AdminClient for banner message integration (#25)
- Add overlays/local for the shared Tailscale front door (#26)
- Add build hash display in footer (#28)
- Migrate to auth-web's shared session


### Documentation
- Update Branding assets section for shared static assets (#14)
- Add full badge row to README (CI, coverage, and the rest) (#23)
- Fix coverage badge URL to point at GitHub Pages (#24)


### Fixed
- Application name
- Remove HPA and PDB from dev overlay
- Remove ExternalDNS annotations from dev Ingress (#20)



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
