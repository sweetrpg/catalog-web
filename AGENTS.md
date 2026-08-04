# AGENTS.md

This file provides guidance to Claude Code, Codex, GitHub Copilot, and other coding agents
working in this repository.

## About This Project

`catalog-web` is a server-rendered Vapor (Swift) frontend for the SweetRPG Catalog domain. It is
the org's first Vapor/Swift-based *web frontend* (as opposed to Swift/Vapor *API* services like
`gamesystems-api`/`profiles-api`) - there is no established platform-wide convention document for
this kind of service yet the way `docs/service-conventions.md` covers Go APIs. This repo is the
reference implementation; conventions here should be written up formally once a second Swift
frontend exists to compare against, per this org's own stated bar for generalizing a pattern.

Pages are rendered server-side (Leaf templates in `Resources/Views/`) from data fetched
server-to-server from backend APIs - not via browser-side `fetch`. This is a deliberate departure
from the client-rendered prototype of this same UI (Claude Design's "SweetRPG catalog app"
project, `RPG Catalogue.dc.html`), which hit CORS failures because it called catalog-api directly
from the browser. Server-to-server calls have no CORS concern at all; CORS middleware in this app
exists only for the (currently unused) case of this app exposing its own API to another origin.

### Backend dependencies

- **catalog-api**: primary data source (volumes, systems, publishers, studios, licenses,
  persons, contributions, reviews). Fully wired up - see `CatalogAPIClient.swift`.
- **game-systems-api**, **profiles-api**, **shelf-api** (currently `library-api` - see
  `sweetrpg/platform`'s `rename-library-to-shelf` OpenSpec change): endpoint shapes not
  confirmed yet. Stubbed in `StubAPIClients.swift` - each returns `nil`/empty rather than
  calling a real endpoint. Replace method bodies as each backend's contract is settled; call
  sites (Controllers) already expect the eventual shape.
- **admin-api** (banner messages, `sweetrpg/admin-api`): `AdminClient.swift`, named to match
  main-web's own `AdminClient` per the `add-banner-messages` OpenSpec change
  (`sweetrpg/platform`). Disabled by default - `baseURL` is `nil` unless `ADMIN_API_URL` is
  set. Fetched as part of `PageMeta.make(req)` (not each controller individually) for
  `platform`, `service:catalog`, and the current page's scope; a 90s Redis-backed cache (via
  `CacheService`, falls through to no caching if Redis isn't configured) and a 2s
  `ClientRequest.timeout` bound the call. Fails open on any error - see `AdminClient.swift`.
  Rendered in `base.leaf`, styled by severity; banner text is plain (no markup), so
  `meta.basePath` prefixing doesn't apply to banner content itself the way it does to this
  app's own generated links.

### Login and the shared session

This app has no login flow of its own. `auth-web` is the platform's sole owner of the Auth0
Authorization Code exchange (see `sweetrpg/platform`'s `add-user-api-authn-authz` OpenSpec
change) - `AuthController.swift`/`Auth0Config.swift`/`ResilientRedisSessionDriver.swift` and this
app's own `/login` page used to exist here and were removed as part of that migration. Every
"log in"/"log out" link (`meta.loginURL`/`meta.logoutURL`, `PageMeta.make`) points at `auth-web`
directly instead.

`Request.currentUser` (`SessionUserAccess.swift`) reads the shared `sweetrpg_session` cookie
`auth-web` writes, via a **separate** Redis connection (`RedisID.sharedSession`, `auth-web`'s own
dedicated instance in `sweetrpg-auth`) from this app's own cache Redis
(`sweetrpg-catalog`). It deliberately does not go through Vapor's `Session`/`SessionsMiddleware`
- touching `req.session` on every request would create and write back a brand-new session for
every anonymous visitor, which is exactly the write this read-only consumer must never make.
Fails open (`nil`) on every error path: disabled, unreachable Redis, missing cookie, missing key,
malformed JSON - same fail-open contract `ResilientRedisSessionDriver` gave every Vapor frontend
before this app's own copy of it was removed.

### Known upstream issue

catalog-api has been observed appending a stray JSON error object after a newline in its
response body when its Redis cache write fails server-side (`sweetrpg/catalog-api#121` fixed the
underlying cause - a `REDIS_PORT` env var collision with Kubernetes' auto-injected service-link
variables - but that fix may not be deployed to every environment yet). `CatalogAPIClient`
defensively decodes only up to the first newline to tolerate this. Don't extend that defensive
parsing's role, and don't treat it as this app's problem to permanently own - it's working around
an upstream bug, not a documented API contract.

### The path-prefix architecture (important - don't break this)

This app runs behind Traefik at `dev.sweetrpg.com/catalog` (dev) / `sweetrpg.com/catalog`
(prod) - a shared host serving multiple frontends, each at its own path. Traefik strips
`/catalog` before the request reaches this app (see `kubernetes/overlays/*/middlewares.yaml`),
so the app's own routes are unprefixed (`/browse`, not `/catalog/browse`). But every link, form
action, static asset URL, and redirect this app generates in HTML has to add the prefix back, or
the *next* browser request won't round-trip through the ingress correctly.

- `Request.basePath` (`AppPaths.swift`) holds this prefix, from `INGRESS_BASE_PATH`.
- Every Leaf template's internal `href`/`action`/`src` uses `#(meta.basePath)` - see `PageMeta`.
  The one exception is `meta.loginURL`/`meta.logoutURL`: `auth-web` sits at `/auth` on the same
  host *root*, not under this app's own `basePath`, so those two are deliberately NOT prefixed
  with `#(meta.basePath)` - see `PageMeta.make`.
- **When adding a new page or partial**: pass `PageMeta(req)` into its context, and prefix every
  internal URL in its template with `#(meta.basePath)`. Missing this is an easy, silent bug -
  it works perfectly in local dev (empty `basePath`) and only breaks once deployed behind the
  ingress prefix.

### Branding assets

Logo, favicon, and stylesheet (a green d20 die in a candy wrapper - "Sweet" + "RPG", the org's
actual current brand mark) are served from `assets-web`'s shared static route, not this repo's
own `Public/` - see `docs/frontend-conventions.md` in `sweetrpg/platform` for the convention and
`AppPaths.swift`'s `sharedAssetsURL` for how this app references them (`SHARED_ASSETS_URL` env
var, falling back to a local `assets-web` instance's address in local dev). `base.leaf`/
`header.leaf` build their `href`/`src` from it. This app used to keep its own copies in
`Public/` before every frontend needing the logo would otherwise drift out of sync with the
others; don't reintroduce a local copy. `sweetrpg.com` itself is a defunct ~2015 placeholder
site with an empty (0-byte) `favicon.ico` and no real logo image - don't pull branding from
there either.

The design (`RPG Catalogue.dc.html`) has no footer content specified - the version/build-date
footer (`partials/footer.leaf`, `BuildInfo.swift`) is this app's own addition, not a departure
from the design.

### Telemetry

Matches the Go services' conventions (`docs/service-conventions.md`'s Telemetry section) with
Swift-appropriate tooling, not identical libraries:

- **Metrics**: `swift-prometheus` bootstrapped as the `swift-metrics` backend
  (`MetricsSetup.swift`), exposed at `/metrics` in the same text exposition format the Go
  services use - Vapor auto-instruments request count/duration once any `MetricsFactory` is
  bootstrapped, no extra middleware needed. Scraped via the same `PodMonitor` pattern.
- **Logging**: a hand-rolled JSON `LogHandler` (`JSONLogHandler.swift`), not a third-party
  package - structured JSON to stdout, one object per line, matching the Go services' structured
  logging rather than their specific library. `LOG_LEVEL` env var (swift-log level names:
  `trace`/`debug`/`info`/`notice`/`warning`/`error`/`critical`), default `info`.
- **Tracing**: `swift-otel`, exported via OTLP/**gRPC** (`TracingSetup.swift`) to the same
  collector the Go services export to via OTLP/HTTP - the version of `swift-otel` pinned here
  only ships a gRPC exporter (no `OTLPHTTP` product exists yet). Uses port 4317, not the Go
  services' 4318 - confirm the collector's gRPC receiver is actually enabled before assuming
  traces are arriving.
- **Errors**: a minimal custom Sentry reporter (`SentryReporter.swift`) hitting Sentry's HTTP
  envelope ingestion API directly, not the official `sentry-cocoa` SDK - that package pulls
  ~230MB of Apple-platform-only XCFrameworks (crash reporting binaries meaningless on a Linux
  server) on `swift package resolve`, a poor fit for this deployment. `SENTRY_DSN` unset means
  reporting silently no-ops, not an error.

## Committing Code

[Conventional Commits](https://www.conventionalcommits.org/): `<type>(<scope>): <description>`.

## Branches and Workflow

Git-flow (see `docs/git-flow.md` in `sweetrpg/platform`): `develop` is the integration branch,
`master` reflects the latest release. Feature/fix branches off `develop`, PR back into `develop`.

## Running Checks Locally

```bash
swift build
swift test
swift format lint --recursive --strict Sources Tests
```

`swift run` serves on `:8080`. Without `REDIS_HOST` set, no response caching. Without
`SHARED_SESSION_REDIS_HOST` set, every visitor reads as logged-out. Without backend URL
overrides, API calls default to in-cluster DNS names that won't resolve outside the cluster - set
`CATALOG_API_URL` (see `BackendConfig.swift`) to a reachable endpoint, e.g.
`https://api.catalog.dev.sweetrpg.com/0`, for local development against real data.
