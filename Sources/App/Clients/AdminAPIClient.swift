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
