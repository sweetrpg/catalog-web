# SweetRPG Catalog Web

[![CI](https://github.com/sweetrpg/catalog-web/actions/workflows/ci.yaml/badge.svg)](https://github.com/sweetrpg/catalog-web/actions/workflows/ci.yaml)
[![Coverage](https://img.shields.io/endpoint?url=https://sweetrpg.github.io/catalog-web/coverage-badge.json)](https://sweetrpg.github.io/catalog-web/)
[![License](https://img.shields.io/github/license/sweetrpg/catalog-web.svg)](https://img.shields.io/github/license/sweetrpg/catalog-web.svg)
[![Issues](https://img.shields.io/github/issues/sweetrpg/catalog-web.svg)](https://img.shields.io/github/issues/sweetrpg/catalog-web.svg)
[![PRs](https://img.shields.io/github/issues-pr/sweetrpg/catalog-web.svg)](https://img.shields.io/github/issues-pr/sweetrpg/catalog-web.svg)
[![Dependabot](https://badgen.net/github/dependabot/sweetrpg/catalog-web)](https://badgen.net/github/dependabot/sweetrpg/catalog-web)
[![Deployment](https://argocd.dev.pilgrimagesoftware.com/api/badge?name=sweetrpg-catalog-web&revision=true&showAppName=true&namespace=sweetrpg-system)](https://argocd.dev.pilgrimagesoftware.com/applications/sweetrpg-catalog-web)

[![Swift](https://img.shields.io/badge/Swift-F05138?style=for-the-badge&logo=swift&logoColor=white)](https://img.shields.io/badge/Swift-F05138?style=for-the-badge&logo=swift&logoColor=white)
[![Built with love](https://ForTheBadge.com/images/badges/built-with-love.svg)](https://ForTheBadge.com/images/badges/built-with-love.svg)

Server-rendered Vapor (Swift) frontend for the SweetRPG Catalog domain: browse volumes, view
details, and (once shelf-api is wired up) track what's on your shelves. The org's first
Vapor/Swift-based web frontend - see `docs/service-conventions.md` in the `platform` repo for
the Go API baseline this doesn't follow, and this repo's own `AGENTS.md` for the conventions it
establishes instead.

Pages are rendered server-side via Leaf templates (`Sources/App/Resources/Views`), pulling data
from [catalog-api](https://github.com/sweetrpg/catalog-api) server-to-server - not via
browser-side `fetch`, which sidesteps the CORS concerns a client-rendered SPA would have. A
prior client-rendered prototype of this UI (Claude Design's "SweetRPG catalog app" project, see
`AGENTS.md`) hit exactly that problem; this app is architected to avoid it.

## Status

Early scaffold. Home, Browse, and Volume Detail pages work against catalog-api. Login is a real
Auth0 Authorization Code flow (needs `AUTH0_DOMAIN`/`AUTH0_CLIENT_ID`/`AUTH0_CLIENT_SECRET`
configured to do anything). My Shelves, and any deeper integration with game-systems-api,
profiles-api, or shelf-api (currently library-api - see `sweetrpg/platform`'s
`rename-library-to-shelf` change), are placeholders - see `AGENTS.md` for what's real vs. stubbed.

## Run locally

```bash
swift run
```

Serves on `:8080`. Without `REDIS_HOST` set, falls back to in-memory sessions and no response
caching - fine for local development. Without backend URL overrides, API calls default to
in-cluster DNS names that won't resolve outside the cluster - set `CATALOG_API_URL` (and friends,
see `BackendConfig.swift`) in a local `.env` to point at a reachable endpoint, e.g. the public dev
ingress.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow and this repo's `AGENTS.md`
for what's implemented vs. placeholder.
