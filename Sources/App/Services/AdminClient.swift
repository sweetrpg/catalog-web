import AdminAPIClient
import Vapor

/// A single, app-lifetime `AdminAPIClient.AdminClient` actor instance, not one per request -
/// the SDK bakes in its own 90s in-memory cache TTL and 2s timeout per actor instance, so a
/// fresh actor per request would defeat that caching entirely. Mirrors `BackendConfig`'s lazy
/// `Application.storage` pattern.
extension Application {
  private struct AdminClientKey: StorageKey {
    typealias Value = AdminAPIClient.AdminClient
  }

  var adminClient: AdminAPIClient.AdminClient {
    if let existing = storage[AdminClientKey.self] {
      return existing
    }
    let client = AdminAPIClient.AdminClient(baseURL: backendConfig.adminAPIURL)
    storage[AdminClientKey.self] = client
    return client
  }
}

extension Request {
  /// Same app-lifetime actor as `Application.adminClient` - never throws (see the SDK's
  /// fail-open contract), so no error handling is needed at call sites.
  var adminClient: AdminAPIClient.AdminClient { application.adminClient }
}

// MARK: - Leaf view models

/// `AdminAPIClient.Banner`/`MaintenanceMode` are `Decodable`-only (the SDK only ever decodes
/// admin-api's responses, never encodes them) - Leaf's context rendering requires `Encodable`
/// to walk the object graph, so both need a local, Leaf-friendly wrapper, same as
/// `LeafVolumeCard`/`LeafUser` etc. in `CatalogController.swift`.

struct LeafBanner: Content {
  let severity: String
  let message: String

  init(_ banner: AdminAPIClient.Banner) {
    self.severity = banner.severity
    self.message = banner.message
  }
}

struct LeafMaintenanceMode: Content {
  let label: String
  let description: String
  let startsAt: String
  let endsAt: String?
  let hasEndsAt: Bool

  init(_ mode: AdminAPIClient.MaintenanceMode) {
    self.label = mode.label
    self.description = mode.description
    self.startsAt = mode.startsAt
    self.endsAt = mode.endsAt
    self.hasEndsAt = mode.endsAt != nil
  }
}
