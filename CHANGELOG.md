
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
