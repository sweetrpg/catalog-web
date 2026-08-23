import CatalogAPIClient
import Foundation
import Tracing
import Vapor

/// Thin wrapper around the `catalog-api-client.swift` SDK: assembles this app's decorated
/// `VolumeViewModel`s from the SDK's raw JSON:API fetches, and adds this app's own Redis
/// response caching (see `CacheService`) - the SDK deliberately has none, since caching backend
/// and TTL policy are a per-app decision, not part of the SDK's contract. Named
/// `CatalogAPIClientService` (not `CatalogAPIClient`) to avoid shadowing the imported SDK
/// module of the same name within this file.
struct CatalogAPIClientService {
  let sdk: CatalogAPIClient
  let cache: CacheService
  private let req: Request

  init(request: Request) {
    self.sdk = CatalogAPIClient(baseURL: request.backendConfig.catalogAPIURL)
    self.cache = request.cacheService
    self.req = request
  }

  /// Loops `page[start]`/`page[limit]` until a short page comes back, accumulating every
  /// record - the dedicated `fetchX()` SDK methods only ask for one page at catalog-api's own
  /// default size (50), so a browse page silently dropped anything past it once a collection
  /// grew past that (persons at 177, volumes at 165 both already do). 100 is catalog-api's own
  /// hard per-page cap (`mongodb.go`'s `QueryMaxSize`), the largest `page[limit]` a single
  /// request can actually get back.
  private func fetchAllPages<Attrs: Codable & Sendable>(
    path: String
  ) async throws -> [JSONAPIDocument<Attrs>.Resource] {
    var all: [JSONAPIDocument<Attrs>.Resource] = []
    var start = 0
    let limit = 100
    while true {
      let doc: JSONAPIDocument<Attrs> = try await sdk.fetch(
        path: "\(path)?page[limit]=\(limit)&page[start]=\(start)")
      all.append(contentsOf: doc.data)
      if doc.data.count < limit { break }
      start += limit
    }
    return all
  }

  func fetchVolumes() async throws -> [VolumeViewModel] {
    try await withSpan("sdk-fetch-volumes") { _ in
      async let volumesResources = getCached("catalog:volumes") {
        try await self.fetchAllPages(path: "/volumes")
          as [JSONAPIDocument<VolumeAttributes>.Resource]
      }
      async let systems = (try? await fetchNameMap(path: "/systems")) ?? [:]
      async let publishers = fetchNameMap(path: "/publishers")
      async let studios = fetchNameMap(path: "/studios")
      async let licenses = fetchNameMap(path: "/licenses")

      let (resources, publisherNames, studioNames, licenseNames) =
        try await (volumesResources, publishers, studios, licenses)
      let systemNames = await systems

      return resources.map { resource in
        decorateVolume(
          id: resource.id,
          attributes: resource.attributes,
          relationships: resource.relationships,
          systemNames: systemNames,
          publisherNames: publisherNames,
          studioNames: studioNames,
          licenseNames: licenseNames)
      }.sorted { $0.title < $1.title }
    }
  }

  /// Decorates a raw volume resource with resolved entity names/ids - shared between
  /// `fetchVolumes()`'s browse-wide fetch and `fetchVolume(id:)`'s single-record fetch.
  /// Takes the resource's parts rather than the resource itself because the list and
  /// single-document wrappers declare distinct (structurally identical) nested `Resource`
  /// types.
  private func decorateVolume(
    id: String,
    attributes: VolumeAttributes,
    relationships: [String: JSONAPIRelationship]?,
    systemNames: [String: String],
    publisherNames: [String: String],
    studioNames: [String: String],
    licenseNames: [String: String]
  ) -> VolumeViewModel {
    let rel = relationships ?? [:]
    func ids(_ key: String) -> [String] {
      rel[key]?.data?.ids ?? []
    }
    func names(_ key: String, from map: [String: String]) -> [String] {
      ids(key).compactMap { map[$0] }
    }
    func refs(_ key: String, from map: [String: String]) -> [EntityRef] {
      (rel[key]?.data?.ids ?? []).compactMap { id in
        map[id].map { EntityRef(id: id, name: $0) }
      }
    }
    return VolumeViewModel(
      id: id,
      title: attributes.title ?? "Untitled",
      description: attributes.description ?? "",
      notes: attributes.notes ?? "",
      tags: (attributes.tags ?? []).map(\.displayName).filter { !$0.isEmpty },
      systemNames: names("system", from: systemNames),
      systemIds: ids("system"),
      publisherNames: names("publisher", from: publisherNames),
      publisherIds: ids("publisher"),
      studioNames: names("studio", from: studioNames),
      studioIds: ids("studio"),
      licenseNames: names("license", from: licenseNames),
      licenseIds: ids("license"),
      properties: (attributes.properties ?? []).map { ($0.name, $0.value) },
      format: attributes.format ?? "",
      sampleAssetIds: attributes.sampleAssetIds ?? [],
      systemRefs: refs("system", from: systemNames),
      publisherRefs: refs("publisher", from: publisherNames),
      studioRefs: refs("studio", from: studioNames),
      licenseRefs: refs("license", from: licenseNames)
    )
  }

  /// Fetches one volume's live record directly by id - one round trip, not a full-collection
  /// walk (`Get*ByID` stays unfiltered per design.md, so this reaches soft-deleted volumes
  /// too; callers gate deleted state separately via `fetchIsDeleted`). Same raw-`req.client`
  /// rationale as `fetchNamedById`: the SDK has no single-volume-by-id method today.
  func fetchVolume(id: String) async throws -> VolumeViewModel? {
    try await withSpan("sdk-fetch-volume") { _ -> VolumeViewModel? in
      let uri = URI(string: req.backendConfig.catalogAPIURL + "/volumes/\(id)")
      let response = try await req.client.get(uri)
      guard response.status == .ok else { return nil }
      let doc = try response.content.decode(JSONAPISingleDocument<VolumeAttributes>.self)
      async let systemNames = (try? await fetchNameMap(path: "/systems")) ?? [:]
      async let publisherNames = (try? await fetchNameMap(path: "/publishers")) ?? [:]
      async let studioNames = (try? await fetchNameMap(path: "/studios")) ?? [:]
      async let licenseNames = (try? await fetchNameMap(path: "/licenses")) ?? [:]
      return decorateVolume(
        id: doc.data.id,
        attributes: doc.data.attributes,
        relationships: doc.data.relationships,
        systemNames: await systemNames,
        publisherNames: await publisherNames,
        studioNames: await studioNames,
        licenseNames: await licenseNames)
    }
  }

  /// Every publisher, sorted by name - the full candidate list the edit page's publisher picker
  /// filters client-side (see design.md's decision: no search endpoint, just filtering the
  /// existing full-collection fetch).
  func fetchPublisherOptions() async throws -> [(id: String, name: String)] {
    try await withSpan("sdk-fetch-publisher-options") { _ in
      let resources = try await getCached("catalog:/publishers") {
        try await self.fetchAllPages(path: "/publishers")
          as [JSONAPIDocument<NamedAttributes>.Resource]
      }

      return resources.map { ($0.id, $0.attributes.displayName) }.sorted { $0.1 < $1.1 }
    }
  }

  /// Every studio, sorted by name - same rationale as `fetchPublisherOptions`.
  func fetchStudioOptions() async throws -> [(id: String, name: String)] {
    try await withSpan("sdk-fetch-studio-options") { _ in
      let resources = try await getCached("catalog:/studios") {
        try await self.fetchAllPages(path: "/studios")
          as [JSONAPIDocument<NamedAttributes>.Resource]
      }
      return resources.map { ($0.id, $0.attributes.displayName) }.sorted { $0.1 < $1.1 }
    }
  }

  /// Every game system, sorted by name - same rationale as `fetchPublisherOptions`. Backs the
  /// volume edit page's system picker (previously missing entirely - unlike publisher/studio,
  /// the volume edit form never wired one up despite catalog-api's Volume record already
  /// carrying a `Systems` relation).
  func fetchSystemOptions() async -> [(id: String, name: String)] {
    await withSpan("sdk-fetch-system-options") { _ in
      let fetch: () async throws -> [(id: String, name: String)] = {
        let resources = try await getCached("catalog:/systems") {
          try await self.fetchAllPages(path: "/systems")
            as [JSONAPIDocument<NamedAttributes>.Resource]
        }
        return resources.map { ($0.id, $0.attributes.displayName) }.sorted { $0.1 < $1.1 }
      }
      return (try? await fetch()) ?? []
    }
  }

  func fetchCredits(volumeID: String) async throws -> [(
    personId: String, role: String, person: String
  )] {
    try await withSpan("sdk-fetch-credits") { _ in
      async let contributionsResources = getCached("catalog:contributions") {
        try await self.fetchAllPages(path: "/contributions")
          as [JSONAPIDocument<ContributionAttributes>.Resource]
      }
      async let personNames = fetchPersonNameMap()

      let (resources, persons) = try await (contributionsResources, personNames)
      return resources.compactMap { resource -> (personId: String, role: String, person: String)? in
        guard let volID = resource.relationships?["volume"]?.data?.ids.first,
          volID == volumeID
        else { return nil }
        guard let personID = resource.relationships?["person"]?.data?.ids.first else { return nil }
        let role = resource.attributes.roles?.first ?? "Contributor"
        return (personId: personID, role: role, person: persons[personID] ?? "Unknown")
      }
    }
  }

  /// Volume ID -> role for every contribution this person is credited on - `fetchPersonVolumes`
  /// already gives the volume list (id/title/cover) but catalog-api's own handler drops role
  /// when deduping contributions into that response, so the person detail page's "Contributed
  /// to" section needs this separate lookup to show what each credit was for.
  func fetchPersonContributionRoles(personID: String) async throws -> [String: String] {
    try await withSpan("sdk-fetch-person-contribution-roles") { _ in
      let resources = try await getCached("catalog:contributions") {
        try await self.fetchAllPages(path: "/contributions")
          as [JSONAPIDocument<ContributionAttributes>.Resource]
      }
      var roles: [String: String] = [:]
      for resource in resources {
        guard let pID = resource.relationships?["person"]?.data?.ids.first, pID == personID,
          let volID = resource.relationships?["volume"]?.data?.ids.first
        else { continue }
        roles[volID] = resource.attributes.roles?.first ?? "Contributor"
      }
      return roles
    }
  }

  func fetchReviews(volumeID: String) async throws -> [(author: String, rating: Int, text: String)]
  {
    try await withSpan("sdk-fetch-reviews") { _ in
      let doc = try await getCached("catalog:reviews") { try await sdk.fetchReviews() }
      return doc.data.compactMap { resource in
        guard let volID = resource.relationships?["volume"]?.data?.ids.first,
          volID == volumeID
        else { return nil }
        return (
          author: resource.attributes.displayAuthor,
          rating: Int(resource.attributes.displayRating.rounded()),
          text: resource.attributes.displayText
        )
      }
    }
  }

  /// Edits a volume, or proposes an edit for review - catalog-api decides which based on the
  /// bearer token's verified roles. This app does no role logic of its own for the write
  /// itself, only for which UI to show (see `CatalogController.editForm`/`submitEdit`).
  func patchVolume(
    id: String, token: String, title: String?, description: String?, notes: String?
  ) async throws -> VolumePatchResult {
    try await withSpan("sdk-patch-volume") { _ in
      try await sdk.patchVolume(
        id: id, token: token, title: title, description: description, notes: notes)
    }
  }

  /// Finalizes the caller's in-flight durable edit session for a volume - see
  /// `CatalogController.submitEdit`.
  func finalizeSession(id: String, token: String) async throws -> VolumePatchResult {
    try await withSpan("sdk-finalize-session") { _ in
      try await sdk.finalizeSession(id: id, token: token)
    }
  }

  /// Accepts a submitted volume version in full (`fields: nil`) or in part. Editor/admin only,
  /// enforced by catalog-api.
  func acceptVolumeVersion(
    volumeID: String, version: Int, token: String, fields: [String]?
  ) async throws -> ReviewVersionResult {
    try await withSpan("sdk-accept-volume-version") { _ in
      try await sdk.acceptVolumeVersion(
        id: volumeID, version: version, token: token, fields: fields)
    }
  }

  /// Rejects a submitted volume version in full, with an optional review note. Editor/admin
  /// only, enforced by catalog-api.
  func rejectVolumeVersion(
    volumeID: String, version: Int, token: String, note: String?
  ) async throws -> ReviewVersionResult {
    try await withSpan("sdk-reject-volume-version") { _ in
      try await sdk.rejectVolumeVersion(id: volumeID, version: version, token: token, note: note)
    }
  }

  /// Lists a volume's version history, newest first.
  func fetchVolumeVersions(volumeID: String, token: String) async throws
    -> [VolumeVersionAttributes]
  {
    try await withSpan("sdk-fetch-volume-versions") { _ in
      try await sdk.fetchVolumeVersions(id: volumeID, token: token)
    }
  }

  /// Fetches one version's full field snapshot, regardless of whether it's current.
  func fetchVolumeVersion(volumeID: String, version: Int, token: String) async throws
    -> VolumeVersionAttributes
  {
    try await withSpan("sdk-fetch-volume-version") { _ in
      try await sdk.fetchVolumeVersion(id: volumeID, version: version, token: token)
    }
  }

  /// Rolls a volume back (or forward) to an arbitrary existing version - admin only, enforced by
  /// catalog-api.
  func setCurrentVolumeVersion(volumeID: String, version: Int, token: String) async throws
    -> VolumeVersionAttributes
  {
    try await withSpan("sdk-set-current-volume-version") { _ in
      try await sdk.setCurrentVolumeVersion(id: volumeID, version: version, token: token)
    }
  }

  /// Every person, sorted by name - the contributor dialog's person picker candidate list
  /// (task 8.1), same client-side-filtering rationale as `fetchPublisherOptions`.
  func fetchPersonOptions() async throws -> [(id: String, name: String)] {
    try await withSpan("sdk-fetch-persons") { _ in
      let resources = try await getCached("catalog:persons") {
        try await self.fetchAllPages(path: "/persons")
          as [JSONAPIDocument<PersonAttributes>.Resource]
      }
      return resources.map { ($0.id, $0.attributes.displayName) }.sorted { $0.1 < $1.1 }
    }
  }

  /// Lists a shared vocabulary's values (contribution-type/property-name/format).
  func fetchVocabulary(type: String, token: String) async throws -> [String] {
    try await withSpan("sdk-fetch-vocabulary") { _ in
      try await sdk.fetchVocabulary(type: type, token: token).values
    }
  }

  /// Adds a new value to a shared vocabulary - editor/admin only, enforced by catalog-api.
  /// Returns the vocabulary's full value list after the add.
  func addVocabularyValue(type: String, value: String, token: String) async throws -> [String] {
    try await withSpan("sdk-add-vocabulary-value") { _ in
      try await sdk.addVocabularyValue(type: type, value: value, token: token).values
    }
  }

  func fetchPublishers() async throws -> [PublisherViewModel] {
    try await withSpan("sdk-fetch-publishers") { _ in
      let resources = try await getCached("catalog:publishers") {
        try await self.fetchAllPages(path: "/publishers")
          as [JSONAPIDocument<PublisherAttributes>.Resource]
      }
      return resources.map { PublisherViewModel(id: $0.id, attributes: $0.attributes) }
        .sorted { $0.name < $1.name }
    }
  }

  func fetchPublisher(id: String) async throws -> PublisherViewModel? {
    try await withSpan("sdk-fetch-publisher") { _ in
      let doc = try await sdk.fetchPublisher(id: id)
      return PublisherViewModel(id: doc.data.id, attributes: doc.data.attributes)
    }
  }

  func fetchPublisherVolumes(id: String) async throws -> [VolumeSummary] {
    try await withSpan("sdk-fetch-publisher-volumes") { _ in
      let doc = try await sdk.fetchPublisherVolumes(id: id)
      return doc.data.map { VolumeSummary(id: $0.id, title: $0.attributes.title ?? "Untitled") }
    }
  }

  func fetchStudios() async throws -> [StudioViewModel] {
    try await withSpan("sdk-fetch-studios") { _ in
      let resources = try await getCached("catalog:studios") {
        try await self.fetchAllPages(path: "/studios")
          as [JSONAPIDocument<StudioAttributes>.Resource]
      }
      return resources.map { StudioViewModel(id: $0.id, attributes: $0.attributes) }
        .sorted { $0.name < $1.name }
    }
  }

  func fetchStudio(id: String) async throws -> StudioViewModel? {
    try await withSpan("sdk-fetch-studio") { _ in
      let doc = try await sdk.fetchStudio(id: id)
      return StudioViewModel(id: doc.data.id, attributes: doc.data.attributes)
    }
  }

  func fetchStudioVolumes(id: String) async throws -> [VolumeSummary] {
    try await withSpan("sdk-fetch-studio-volumes") { _ in
      let doc = try await sdk.fetchStudioVolumes(id: id)
      return doc.data.map { VolumeSummary(id: $0.id, title: $0.attributes.title ?? "Untitled") }
    }
  }

  func fetchPersonsCatalog() async throws -> [PersonViewModel] {
    try await withSpan("sdk-fetch-persons-catalog") { _ in
      let resources = try await getCached("catalog:persons-list") {
        try await self.fetchAllPages(path: "/persons")
          as [JSONAPIDocument<PersonAttributes>.Resource]
      }
      return resources.map { PersonViewModel(id: $0.id, attributes: $0.attributes) }
        .sorted { $0.name < $1.name }
    }
  }

  func fetchPerson(id: String) async throws -> PersonViewModel? {
    try await withSpan("sdk-fetch-person") { _ in
      let doc = try await sdk.fetchPerson(id: id)
      return PersonViewModel(id: doc.data.id, attributes: doc.data.attributes)
    }
  }

  func fetchPersonVolumes(id: String) async throws -> [VolumeSummary] {
    try await withSpan("sdk-fetch-person-volumes") { _ in
      let doc = try await sdk.fetchPersonVolumes(id: id)
      return doc.data.map { VolumeSummary(id: $0.id, title: $0.attributes.title ?? "Untitled") }
    }
  }

  func fetchLicenses() async throws -> [LicenseViewModel] {
    try await withSpan("sdk-fetch-licenses") { _ in
      let resources = try await getCached("catalog:licenses-list") {
        try await self.fetchAllPages(path: "/licenses")
          as [JSONAPIDocument<LicenseAttributes>.Resource]
      }
      return resources.map { LicenseViewModel(id: $0.id, attributes: $0.attributes) }
        .sorted { $0.title < $1.title }
    }
  }

  func fetchLicense(id: String) async throws -> LicenseViewModel? {
    try await withSpan("sdk-fetch-license") { _ in
      let doc = try await sdk.fetchLicense(id: id)
      return LicenseViewModel(id: doc.data.id, attributes: doc.data.attributes)
    }
  }

  func fetchLicenseVolumes(id: String) async throws -> [VolumeSummary] {
    try await withSpan("sdk-fetch-license-volumes") { _ in
      let doc = try await sdk.fetchLicenseVolumes(id: id)
      return doc.data.map { VolumeSummary(id: $0.id, title: $0.attributes.title ?? "Untitled") }
    }
  }

  /// Outcome of a generic entity PATCH - the applied document's contents aren't used by any
  /// caller (the controller just redirects), so this discards them rather than threading a
  /// per-type `Attributes` generic parameter up through the controller layer.
  enum PatchOutcome {
    case applied
    case proposed(SubmittedVersionResponse)
  }

  /// Edits a publisher/studio/person/license, or proposes an edit for review - the generic
  /// counterpart of `patchVolume`. `path` is the resource's collection path (e.g.
  /// `/publishers`). Decodes the applied-case response as `NamedAttributes` regardless of the
  /// real entity type purely to satisfy the SDK call's generic parameter - its fields
  /// (`name`/`title`, both optional) decode successfully against any of the four types' actual
  /// response shapes without needing to match them, since the decoded value itself is unused.
  func patchEntity(path: String, id: String, token: String, fields: [String: String])
    async throws -> PatchOutcome
  {
    let result: EntityPatchResult<NamedAttributes> = try await sdk.patchEntity(
      path: path, id: id, token: token, fields: fields)
    switch result {
    case .applied: return .applied
    case .proposed(let submission): return .proposed(submission)
    }
  }

  /// Lists a publisher/studio/person/license's version history, newest first - the generic
  /// counterpart of `fetchVolumeVersions(volumeID:token:)`.
  func fetchEntityVersions<T: EntityVersionAttributes>(path: String, id: String, token: String)
    async throws -> [T]
  {
    try await withSpan("sdk-fetch-entity-versions") { _ in
      try await sdk.fetchEntityVersions(path: path, id: id, token: token)
    }
  }

  /// Accepts a publisher/studio/person/license submitted version, in full or in part - the
  /// generic counterpart of `acceptVolumeVersion`. Editor/admin only, enforced by catalog-api.
  func acceptEntityVersion(
    path: String, id: String, version: Int, token: String, fields: [String]?
  ) async throws -> ReviewVersionResult {
    try await withSpan("sdk-accept-entity-version") { _ in
      try await sdk.acceptEntityVersion(
        path: path, id: id, version: version, token: token, fields: fields)
    }
  }

  /// Rejects a publisher/studio/person/license submitted version - the generic counterpart of
  /// `rejectVolumeVersion`. Editor/admin only, enforced by catalog-api.
  func rejectEntityVersion(
    path: String, id: String, version: Int, token: String, note: String?
  ) async throws -> ReviewVersionResult {
    try await withSpan("sdk-reject-entity-version") { _ in
      try await sdk.rejectEntityVersion(
        path: path, id: id, version: version, token: token, note: note)
    }
  }

  /// Creates a publisher/studio/person/license - the generic counterpart of `patchEntity`, for
  /// catalog-api's `POST /:type` route (sweetrpg/catalog-api#220). Implemented as a raw
  /// `req.client` call rather than through `sdk` - the `catalog-api-client.swift` SDK (pinned
  /// pre-1.0) doesn't have a create method yet, and adding one there plus a version bump wasn't
  /// worth it for the one page (this create form) that needs it; revisit if a second consumer of
  /// entity creation shows up. `path` is the resource's collection path (e.g. `/publishers`).
  /// Returns the new record's id.
  func createEntity(path: String, token: String, fields: [String: String]) async throws -> String {
    try await withSpan("create-entity") { _ in
      let uri = URI(string: req.backendConfig.catalogAPIURL + path)
      let response = try await req.client.post(uri) { clientReq in
        clientReq.headers.bearerAuthorization = BearerAuthorization(token: token)
        try clientReq.content.encode(fields, as: .json)
      }
      guard response.status == .created else {
        throw Abort(response.status, reason: "catalog-api create failed")
      }
      let doc = try response.content.decode(JSONAPISingleDocument<NamedAttributes>.self)
      return doc.data.id
    }
  }

  /// One entry's outcome in a bulk-create response - success/id for a created record, or an
  /// error message, never both (matches catalog-api's bulkCreateResult).
  struct BulkCreateResult: Content {
    let success: Bool
    let id: String?
    let error: String?
  }

  private struct BulkCreateResponse: Content {
    let results: [BulkCreateResult]
  }

  /// Bulk-creates N persons from a single request (catalog-entity-bulk-add) - each entry
  /// succeeds or fails independently, so a caller gets back one result per input entry rather
  /// than an all-or-nothing outcome. Same raw-`req.client` rationale as `createEntity` above -
  /// no `catalog-api-client.swift` SDK method exists for this yet.
  func bulkCreatePersons(fields: [[String: String]], token: String) async throws
    -> [BulkCreateResult]
  {
    try await withSpan("bulk-create-persons") { _ in
      let uri = URI(string: req.backendConfig.catalogAPIURL + "/persons/bulk")
      let response = try await req.client.post(uri) { clientReq in
        clientReq.headers.bearerAuthorization = BearerAuthorization(token: token)
        try clientReq.content.encode(fields, as: .json)
      }
      guard response.status == .ok else {
        throw Abort(response.status, reason: "catalog-api bulk create failed")
      }
      return try response.content.decode(BulkCreateResponse.self).results
    }
  }

  /// Edits a license's string fields and (optionally) its `tags` array in one PATCH - the
  /// license-specific counterpart of `patchEntity`, which only encodes a `[String: String]` body
  /// and so can't carry `tags` (catalog-api's one array-valued entity field, sweetrpg/
  /// catalog-api#220's `arrayFields`). Combining both into a single request matters, not just for
  /// fewer round trips: catalog-api creates one new version per PATCH request, so calling
  /// `patchEntity` and a separate tags-only PATCH back to back would create two versions (two
  /// separate submitted proposals for a submitter) instead of one unified edit. Same raw-
  /// `req.client` rationale as `createEntity` above.
  func patchLicenseFields(id: String, token: String, fields: [String: String], tags: [String]?)
    async throws -> PatchOutcome
  {
    try await withSpan("patch-license-fields") { _ in
      let uri = URI(string: req.backendConfig.catalogAPIURL + "/licenses/\(id)")
      let response = try await req.client.patch(uri) { clientReq in
        clientReq.headers.bearerAuthorization = BearerAuthorization(token: token)
        var body: [String: Any] = fields
        if let tags {
          body["tags"] = tags
        }
        let data = try JSONSerialization.data(withJSONObject: body)
        clientReq.headers.contentType = .json
        clientReq.body = ByteBuffer(data: data)
      }
      switch response.status {
      case .ok:
        _ = try response.content.decode(JSONAPISingleDocument<NamedAttributes>.self)
        return .applied
      case .accepted:
        return .proposed(try response.content.decode(SubmittedVersionResponse.self))
      default:
        throw Abort(response.status, reason: "catalog-api license update failed")
      }
    }
  }

  /// Sets the full list of volumes an entity is associated with (full-replace) - catalog-api's
  /// `PATCH <path>/:id/volumes` (sweetrpg/catalog-api#220), editor/admin only. Generic over
  /// `path` (`/licenses`, `/studios`, ...) since the route shape and semantics are identical
  /// per entity type - only which volume field it writes differs, and that's catalog-api's
  /// concern, not this client's. Same raw-`req.client` rationale as `createEntity` above.
  func patchEntityVolumes(path: String, id: String, token: String, volumeIds: [String])
    async throws
  {
    try await withSpan("patch-entity-volumes") { _ in
      let uri = URI(string: req.backendConfig.catalogAPIURL + "\(path)/\(id)/volumes")
      let response = try await req.client.patch(uri) { clientReq in
        clientReq.headers.bearerAuthorization = BearerAuthorization(token: token)
        try clientReq.content.encode(["volumeIds": volumeIds], as: .json)
      }
      guard response.status == .ok else {
        throw Abort(response.status, reason: "catalog-api \(path) volumes update failed")
      }
    }
  }

  private struct DeletionAttributes: Codable, Sendable {
    let deletedAt: Date?
    enum CodingKeys: String, CodingKey {
      case deletedAt = "deleted_at"
    }
  }

  /// Whether a publisher/studio/person/license/system/volume is currently soft-deleted - gates a
  /// detail page's Delete vs. Restore action (task 3.2). `path` is the resource's own path (e.g.
  /// `/publishers/abc123`). Same raw-`req.client` rationale as `fetchNamedById` - the SDK's
  /// attribute types don't decode `deletedAt`.
  func fetchIsDeleted(path: String) async -> Bool {
    (try? await withSpan("fetch-is-deleted") { _ -> Bool in
      let uri = URI(string: req.backendConfig.catalogAPIURL + path)
      let response = try await req.client.get(uri)
      guard response.status == .ok else { return false }
      let doc = try response.content.decode(JSONAPISingleDocument<DeletionAttributes>.self)
      return doc.data.attributes.deletedAt != nil
    }) ?? false
  }

  /// Fetches one record's display name directly by id, bypassing the (deleted-record-excluding)
  /// list endpoints - `Get*ByID` stays unfiltered per design.md, so this reaches a soft-deleted
  /// record's name too. Returns `nil` on any error (not-found or otherwise) rather than
  /// throwing - callers use this as a best-effort fallback, not a required fetch. Same raw-
  /// `req.client` rationale as `createEntity`: the SDK has no single-record-by-arbitrary-path
  /// method today.
  private func fetchNamedById(path: String, id: String) async -> String? {
    try? await withSpan("fetch-named-by-id") { _ in
      let uri = URI(string: req.backendConfig.catalogAPIURL + path + "/\(id)")
      let response = try await req.client.get(uri)
      guard response.status == .ok else { return nil }
      let doc = try response.content.decode(JSONAPISingleDocument<NamedAttributes>.self)
      return doc.data.attributes.displayName
    }
  }

  /// Resolves any publisher/studio/license/system reference on a volume that's soft-deleted
  /// since the volume linked it, so its detail/edit page can label it "(deleted)" instead of
  /// silently dropping it (task 4.1) - a reference id present on the volume but missing from the
  /// live (non-deleted) name map is, by construction, a deleted record (the map is built from
  /// the same filtered `List*` calls that exclude deleted records - see design.md). Detail-page-
  /// only: called once per single-volume view, not from `fetchVolumes()`'s browse-wide fetch,
  /// since the extra per-deleted-reference round trip is fine for one volume, not every volume
  /// in a listing.
  func resolveDeletedReferences(_ volume: VolumeViewModel) async -> VolumeViewModel {
    async let publisherMap = fetchNameMap(path: "/publishers")
    async let studioMap = fetchNameMap(path: "/studios")
    async let licenseMap = fetchNameMap(path: "/licenses")
    async let systemMap = fetchNameMap(path: "/systems")

    var volume = volume
    volume.publisherRefs = await resolveRefs(
      ids: volume.publisherIds, liveMap: (try? await publisherMap) ?? [:], path: "/publishers")
    volume.studioRefs = await resolveRefs(
      ids: volume.studioIds, liveMap: (try? await studioMap) ?? [:], path: "/studios")
    volume.licenseRefs = await resolveRefs(
      ids: volume.licenseIds, liveMap: (try? await licenseMap) ?? [:], path: "/licenses")
    volume.systemRefs = await resolveRefs(
      ids: volume.systemIds, liveMap: (try? await systemMap) ?? [:], path: "/systems")
    volume.systemNames = await resolveNames(
      ids: volume.systemIds, liveMap: (try? await systemMap) ?? [:], path: "/systems")
    return volume
  }

  private func resolveRefs(ids: [String], liveMap: [String: String], path: String) async
    -> [EntityRef]
  {
    var result: [EntityRef] = []
    for id in ids {
      if let name = liveMap[id] {
        result.append(EntityRef(id: id, name: name))
      } else if let name = await fetchNamedById(path: path, id: id) {
        result.append(EntityRef(id: id, name: name, isDeleted: true))
      }
    }
    return result
  }

  private func resolveNames(ids: [String], liveMap: [String: String], path: String) async
    -> [String]
  {
    var result: [String] = []
    for id in ids {
      if let name = liveMap[id] {
        result.append(name)
      } else if let name = await fetchNamedById(path: path, id: id) {
        result.append("\(name) (deleted)")
      }
    }
    return result
  }

  /// Evicts every cache key that could still be serving this entity type's now-stale list -
  /// called after a delete/restore (task 3.4) so the change is reflected in browse/pickers
  /// immediately, not after the normal 60s TTL. `path` is the resource's collection path (e.g.
  /// `/publishers`) - every cache key any `fetch*`/`fetchNameMap` call site above uses for that
  /// type, kept in sync with them by hand since they're plain string literals, not derived from
  /// one shared source.
  func invalidateListCache(path: String) async {
    let keysByPath: [String: [String]] = [
      "/publishers": ["catalog:publishers", "catalog:/publishers", "catalog:stats"],
      "/studios": ["catalog:studios", "catalog:/studios", "catalog:stats"],
      "/persons": ["catalog:persons", "catalog:persons-list", "catalog:stats"],
      "/licenses": ["catalog:licenses-list", "catalog:/licenses", "catalog:stats"],
      "/systems": ["catalog:/systems", "catalog:stats"],
      "/volumes": ["catalog:volumes", "catalog:stats"],
    ]
    await cache.delete(keysByPath[path] ?? [])
  }

  /// Soft-deletes a publisher/studio/person/license/system/volume - catalog-api's
  /// `DELETE /<type>/:id` (sweetrpg/catalog-api#228), admin only. `path` is the resource's own
  /// path (e.g. `/publishers/abc123`), not its collection path.
  func deleteEntity(path: String, token: String) async throws {
    try await withSpan("delete-entity") { _ in
      let uri = URI(string: req.backendConfig.catalogAPIURL + path)
      let response = try await req.client.delete(uri) { clientReq in
        clientReq.headers.bearerAuthorization = BearerAuthorization(token: token)
      }
      guard response.status == .noContent else {
        throw Abort(response.status, reason: "catalog-api delete failed")
      }
    }
  }

  /// Restores a soft-deleted entity - catalog-api's `POST /<type>/:id/restore`, admin only.
  /// `path` is the resource's own path (e.g. `/publishers/abc123`).
  func restoreEntity(path: String, token: String) async throws {
    try await withSpan("restore-entity") { _ in
      let uri = URI(string: req.backendConfig.catalogAPIURL + path + "/restore")
      let response = try await req.client.post(uri) { clientReq in
        clientReq.headers.bearerAuthorization = BearerAuthorization(token: token)
      }
      guard response.status == .ok else {
        throw Abort(response.status, reason: "catalog-api restore failed")
      }
    }
  }

  private func fetchNameMap(path: String) async throws -> [String: String] {
    try await withSpan("sdk-fetch-named") { _ in
      let resources = try await getCached("catalog:\(path)") {
        try await self.fetchAllPages(path: path) as [JSONAPIDocument<NamedAttributes>.Resource]
      }
      return Dictionary(uniqueKeysWithValues: resources.map { ($0.id, $0.attributes.displayName) })
    }
  }

  private func fetchPersonNameMap() async throws -> [String: String] {
    try await withSpan("sdk-fetch-persons") { _ in
      let resources = try await getCached("catalog:persons") {
        try await self.fetchAllPages(path: "/persons")
          as [JSONAPIDocument<PersonAttributes>.Resource]
      }
      return Dictionary(uniqueKeysWithValues: resources.map { ($0.id, $0.attributes.displayName) })
    }
  }

  /// Catalog-wide summary (total volume count, most recent update) for the landing page - one
  /// call instead of counting whatever page a paginated volume list happened to return.
  func fetchCatalogStats() async throws -> CatalogStats {
    try await withSpan("sdk-fetch-catalog-stats") { _ in
      try await getCached("catalog:stats") { try await sdk.fetchCatalogStats() }
    }
  }

  private func getCached<T: Codable & Sendable>(
    _ cacheKey: String, fetch: @Sendable () async throws -> T
  ) async throws -> T {
    try await withSpan("sdk-cache-get-or-set") { _ in
      try await cache.getOrSet(cacheKey, ttlSeconds: 60, fetch: fetch)
    }
  }

  /// Every cache key that can hold a list/name-map of the entity type at `path` - not a fully
  /// consistent naming scheme (some keys carry the leading slash, some don't, "persons" also has
  /// a "-list" variant), so this enumerates the actual keys in use rather than deriving them.
  /// Called after create/edit so a newly added or renamed publisher/studio/person shows up in
  /// pickers immediately instead of waiting out the 60s TTL - see submitCreate/submitEdit.
  private static let entityListCacheKeys: [String: [String]] = [
    "/persons": ["catalog:persons", "catalog:persons-list"],
    "/publishers": ["catalog:publishers", "catalog:/publishers"],
    "/studios": ["catalog:studios", "catalog:/studios"],
    "/licenses": ["catalog:licenses-list"],
    "/volumes": ["catalog:volumes"],
  ]

  func invalidateEntityListCache(path: String) async {
    await cache.delete(Self.entityListCacheKeys[path] ?? [])
  }
}

extension Request {
  var catalogAPI: CatalogAPIClientService { CatalogAPIClientService(request: self) }
}
