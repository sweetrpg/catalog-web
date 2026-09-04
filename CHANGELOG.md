
## 0.47.2 - 2026-09-04

### Fixed
- Human-friendly labels for DTRPG-imported property keys



## 0.47.1 - 2026-09-04

### Fixed
- Hide entity-create popups until opened



## 0.47.0 - 2026-09-02

### Added
- Render system names from denormalized systemTitles



## 0.46.0 - 2026-09-02

### Added
- Rich tooltips for soft-delete and version-state controls (#207)


## 0.45.0 - 2026-09-01

### Added
- Group volume detail credits by person (#202)



## 0.44.3 - 2026-08-29


## 0.44.3 - 2026-08-29

### Fixed
- Drop redundant onload hack, reveal avatar fallback on image error



## 0.44.2 - 2026-08-28

### Changed
- Update game-systems-api URL and env var


### Fixed
- Locale strings for shelf/library/game-room
- Update name
- Align app-switcher destinations with the shared spec



## 0.44.1 - 2026-08-28

### Fixed
- Point Profile link at users-web's real profile route



## 0.44.0 - 2026-08-27

### Added
- Add inline entity creation popup to volume edit page


### Changed
- Rename shelf-api references to game-room-api


### Fixed
- Use icon buttons for publisher edit/delete actions



## 0.43.0 - 2026-08-24

### Added
- Add tag cloud display and refactor tab labels
- Link credit persons to their records and flow credits into columns



## 0.42.0 - 2026-08-24

### Added
- Add tabbed content area to volume detail page


### Fixed
- Keep side-by-side association layout for header system/license sections



## 0.41.0 - 2026-08-24

### Added
- Show contribution count on person browse cards


### Fixed
- Lay out system/publisher/studio/license sections horizontally
- Render volumes/browse after the template path move



## 0.40.0 - 2026-08-23

### Added
- Add tag editing to the volume edit page



## 0.39.0 - 2026-08-23

### Added
- Extract user-facing strings into locale resources


### Fixed
- Use singular role attribute from SDK



## 0.38.0 - 2026-08-23

### Added
- Structured entry/exit and decision-point logging across volume edit flow


### Fixed
- Fetch volume detail by id instead of walking the full collection



## 0.37.2 - 2026-08-22

### Fixed
- Deduplicate volume tests left in both AppTests.swift and VolumesTests.swift
- Add error reason for missing volume ID
- Add some logging
- Log and Sentry-report swallowed finalize-session failures
- Show a human-friendly banner when finalize fails


## 0.37.1 - 2026-08-21

### Fixed
- Recolor delete/restore icons via CSS mask, not filter
- Update template names for volumes/ leaf path rename
- Leaf paths in tests



## 0.37.0 - 2026-08-21

### Added
- Add real pagination controls, fix the underlying page-cap bug



## 0.36.0 - 2026-08-21

### Added
- Fall back to a placeholder image, not text, when a volume has no cover


### Fixed
- Edit/Delete as icon buttons in the header, not stacked text buttons
- Correct icon paths, add destructive styling to Delete/Restore
- Fix broken delete/restore icons, add destructive styling
- Contributor dialog - plus icon for Add, move Close to panel header



## 0.35.1 - 2026-08-21

### Fixed
- Fail open when /systems is unavailable



## 0.35.0 - 2026-08-21

### Added
- Add deed/legal-code preview toggle, default deed open


### Fixed
- Add missing catalog-web-health-token Password generator
- Fix cpu resource limit quantity that never matched ArgoCD's applied manifest
- Remove implicit whitespace above the Deed/Legal code toggle



## 0.34.0 - 2026-08-20

### Added
- Make each summary tile clickable to its browse page
- Add web-misc secret to deployment and dev overlay
- Rename Volumes to Contributed to, show role per volume
- Add Volumes picker to the edit page


### Fixed
- Align title with cover top, Properties Add buttons as icons
- Volumes sits beside form fields, not below them
- Back links say where they go, not generic 'Back'



## 0.33.0 - 2026-08-20

### Added
- Admin-only delete/restore UI, reference-degradation labeling



## 0.32.0 - 2026-08-20

### Added
- Tags autocomplete picker, wider edit form
- Add volume-association picker to studio edit page
- Add game system association to volume edit page
- Bulk-add persons page and API client, gated to editor/admin
- Wire bulk-add button and post-submit result banner


### Fixed
- Prefix tag-cloud links with basePath
- Show credit person name before contribution type
- Render submitter/reviewer sub as a readable label
- Open Deed by default, only divider Deed from Legal code
- Put Add-X button on the same row as search/sort
- Invalidate entity list-cache on create/edit
- Update license-edit and version-detail tests for prior commits
- Contributor dialog layout, icon buttons, and type pre-fill
- Invalidate the volumes list cache after a live edit
- Merge browse links into hero row, 3-col responsive stat grid
- Rename bulk_created/bulk_failed/bulk_errors query fields to camelCase



## 0.31.0 - 2026-08-19

### Added
- Per-entity-type summary cards, replacing the volumes grid



## 0.30.0 - 2026-08-19

### Added
- Add app switcher grid next to avatar menu



## 0.29.0 - 2026-08-19


## 0.29.0 - 2026-08-19

### Added
- Add create-new forms for publisher/studio/license/person
- Edit tags and associated volumes from the license edit page



## 0.28.0 - 2026-08-19

### Added
- Wire up the real catalog stats endpoint
- Render volume description as Markdown, bound its height, restyle header actions


### Fixed
- Remove extra blank space above/below license text
- Raise body-size limit past 16kb, route 413 to the branded error page
- Route 409 Conflict to the branded error page too



## 0.27.0 - 2026-08-19

### Added
- Store format as a property, normalize keys, localize/humanize display



## 0.26.1 - 2026-08-19

### Fixed
- Lingo localizationsDir path, sample button layout, form actions, contributor add-flow
- Properties row layout, section spacing dividers
- Move notes field to the bottom, above save/discard
- Tint field edit-trigger buttons in the accent color



## 0.26.0 - 2026-08-18

### Added
- Add publisher volume-count label, share Lingo helper across browse pages


### Fixed
- Cover image, title field, tag pickers, chip remove, styling
- Version history was silently swallowing fetch failures as empty
- Show deed/legal_code, textarea + select field kinds, lowercase footer
- Shorten license edit test name to satisfy swift-format line length



## 0.25.0 - 2026-08-18


## 0.25.0 - 2026-08-18

### Added
- Add name sort order control next to search



## 0.24.0 - 2026-08-18

### Added
- Redesign license detail page layout



## 0.23.1 - 2026-08-18

### Fixed
- Volume typeahead broken by HTML-escaped JSON; redesign edit page controls



## 0.23.0 - 2026-08-18

### Added
- Version-history UI and review rewire for all entity types, remove proposed_changes
- Version-history UI and review rewire for all entity types


### Fixed
- Bump catalog-api-client.swift constraint to from: 0.1.0
- Wire up Vapor's TracingMiddleware



## 0.22.0 - 2026-08-17

### Added
- Add logging to EditSessionStore operations


### Changed
- Move log inside span for better tracing



## 0.21.0 - 2026-08-16

### Added
- Add volume title as alt text for cover images and remove svg extension from cover asset path



## 0.20.1 - 2026-08-16

### Fixed
- Update Swift version in release workflow


## 0.20.0 - 2026-08-16

### Added
- Add spans to volume controller endpoints
- Add distributed tracing spans to catalog controllers
- Add tracing everywhere
- More tracing
- Add tracing to SDK
- Add tracing to middlewares


### Changed
- Move AppPaths to Miscellaneous directory
- Reorder imports to follow convention


### Fixed
- Remove unnecessary try
- Try to make the build work, update Swift version
- Put the candle back



## 0.19.0 - 2026-08-15

### Added
- Add logging and mark volume fetch as TODO


### Fixed
- Use sharedURL for theme.css path



## 0.18.0 - 2026-08-15

### Added
- Add assetsURL for catalog assets and update sharedURL comment
- Add lastUpdated display to home page


### Changed
- Split shared assets URL into shared and assets URLs
- Split CatalogEntitiesController into per-entity controllers and view models
- More reorganization



## 0.17.0 - 2026-08-14

### Added
- Route generic error status codes to shared-web


### Fixed
- Decode the shared session's expiry as RFC 3339



## 0.16.0 - 2026-08-14

### Added
- Add volume version-history and single-version views



## 0.15.0 - 2026-08-13

### Added
- Fluid inline editing for title/description/notes/cover
- Session-backed volume editing (durable-volume-editing)
- Publisher/studio linking on the volume edit page
- Contributor linking on the volume edit page
- Properties table on the volume detail and edit pages
- Format selector on the volume edit page
- Sample pages on the volume detail and edit pages


### Fixed
- Drop live-Redis round-trip tests, CI has no Redis service



## 0.14.0 - 2026-08-12

### Added
- Add browse/detail/edit pages for publishers, studios, persons, licenses



## 0.13.0 - 2026-08-12

### Added
- Report build version on /status/ping



## 0.12.1 - 2026-08-12

### Fixed
- Stop conflicts banner from showing with no conflicts
- Pass return_to on logout link



## 0.12.0 - 2026-08-12

### Added
- Add cover-upload control to the volume detail page


### Fixed
- Fail open when fetching pending proposed changes



## 0.11.0 - 2026-08-11

### Added
- Add cover-upload control to the volume detail page



## 0.10.0 - 2026-08-11

### Added
- Honor shared session expiry field



## 0.9.0 - 2026-08-11

### Added
- Add edit action and proposed-change review UI


### Fixed
- Match avatar badge accent color to main-web



## 0.8.1 - 2026-08-09

### Fixed
- Update shared static asset paths for assets-web's css/img/js reorg



## 0.8.0 - 2026-08-08

### Added
- Always show avatar menu with theme selector in catalog-web
- Color Log Out with the danger/critical color
- Render volume covers and structured detail metadata


### Fixed
- Hide the fallback letter once the Gravatar image loads
- Hide the fallback text once a cover image loads



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
