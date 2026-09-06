import Vapor

/// Base URLs for every backend this app talks to. Calls happen server-to-server (this app's
/// pods to the target service's ClusterIP Service), so these default to in-cluster DNS names -
/// not the public ingress hosts - matching the pattern in docs/service-conventions.md. Override
/// via env var for local development against a port-forwarded or public dev endpoint.
struct BackendConfig {
  let catalogAPIURL: String
  let gameSystemsAPIURL: String
  let profilesAPIURL: String
  let gameRoomAPIURL: String
  /// `admin-api`'s base URL, for banner messages. Unlike every other backend above, this has
  /// no in-cluster-DNS default - `nil` unless `ADMIN_API_URL` is explicitly set, so a deploy
  /// with the var unset makes zero calls to admin-api (see AdminClient.swift).
  let adminAPIURL: String?
  /// How many tags the landing page/browse tag cloud asks for - catalog-api clamps its own
  /// `limit` param (default 20, cap 100), but this default matches what the tag cloud wants.
  let volumeTagsLimit: Int

  static func fromEnvironment() -> BackendConfig {
    BackendConfig(
      // No /0 or /1 suffix: that API-version prefix only exists on catalog-api's public
      // ingress (stripped by its Traefik middleware) - direct Service-to-Service calls bypass
      // the ingress entirely and hit catalog-api's unprefixed routes directly.
      catalogAPIURL: Environment.get("CATALOG_API_URL")
        ?? "http://api-v1.sweetrpg-catalog.svc.cluster.local:8000",
      gameSystemsAPIURL: Environment.get("GAME_SYSTEMS_API_URL")
        ?? "http://api-v1.sweetrpg-game-systems.svc.cluster.local:8000",
      profilesAPIURL: Environment.get("PROFILES_API_URL")
        ?? "http://api-v1.sweetrpg-profiles.svc.cluster.local:8000",
      gameRoomAPIURL: Environment.get("GAME_ROOM_API_URL")
        ?? "http://api-v1.sweetrpg-game-room.svc.cluster.local:8000",
      adminAPIURL: Environment.get("ADMIN_API_URL"),
      volumeTagsLimit: Environment.get("VOLUME_TAGS_LIMIT").flatMap(Int.init) ?? 20
    )
  }
}

extension Application {
  private struct BackendConfigKey: StorageKey {
    typealias Value = BackendConfig
  }

  var backendConfig: BackendConfig {
    get {
      guard let config = storage[BackendConfigKey.self] else {
        let config = BackendConfig.fromEnvironment()
        storage[BackendConfigKey.self] = config
        return config
      }
      return config
    }
    set { storage[BackendConfigKey.self] = newValue }
  }
}

extension Request {
  var backendConfig: BackendConfig { application.backendConfig }
}
