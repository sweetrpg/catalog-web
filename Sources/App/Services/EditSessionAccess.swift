import Foundation
import Redis
import Tracing
import Vapor

/// Names the Redis connection this app reads/writes the durable volume-edit session store on -
/// a distinct connection from both this app's own cache Redis (`.default`, DB 1) and the shared
/// auth session Redis (`.sharedSession`), pointed instead at DB 2 on catalog-api's own Redis
/// instance in `sweetrpg-catalog`. See docs/frontend-conventions.md's edit-session schema in
/// sweetrpg/platform, and `configure.swift`.
extension RedisID {
  static let editSession = RedisID("editSession")
}

/// A `fields` value: catalog-api's `patchVolumeRequest` (what `finalize-session` decodes a
/// session's `fields` map into) has both scalar fields (title, description, notes, format -
/// plain strings) and list-shaped ones (publisherIds/studioIds - `[]string`; credits/properties
/// - `[]struct{...}`), so `fields` can't be a homogeneous `[String: String]`. Covers exactly
/// the shapes Volume's editable fields actually need, not general-purpose JSON.
enum FieldValue: Codable, Equatable, Sendable {
  case string(String)
  case stringArray([String])
  case objectArray([[String: String]])

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([String].self) {
      self = .stringArray(value)
    } else if let value = try? container.decode([[String: String]].self) {
      self = .objectArray(value)
    } else {
      throw DecodingError.typeMismatch(
        FieldValue.self,
        DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription: "Expected a string, an array of strings, or an array of objects"))
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value): try container.encode(value)
    case .stringArray(let value): try container.encode(value)
    case .objectArray(let value): try container.encode(value)
    }
  }
}

/// Mirrors the JSON schema catalog-api's `editsession.Session` reads at finalize time - the two
/// sides are independently maintained (Swift here, Go there) but must agree on wire shape.
/// `createdAt`/`updatedAt` are encoded/decoded manually (not through Redis's `asJSON`/`toJSON`
/// convenience helpers, whose default `JSONEncoder` encodes `Date` as a epoch-seconds number,
/// not the RFC3339 string Go's `time.Time` JSON unmarshaling expects) - see `EditSessionStore`.
struct EditSession: Codable, Sendable {
  var recordId: String
  var fields: [String: FieldValue]
  var stagedCoverAssetId: String?
  var sampleAssetIds: [String]?
  var createdAt: Date
  var updatedAt: Date

  /// Reads `key` as a string field, or `nil` if absent or a different shape.
  func stringField(_ key: String) -> String? {
    if case .string(let value)? = fields[key] { return value }
    return nil
  }

  /// Reads `key` as a string-array field, or `nil` if absent or a different shape.
  func stringArrayField(_ key: String) -> [String]? {
    if case .stringArray(let value)? = fields[key] { return value }
    return nil
  }

  /// Reads `key` as an object-array field (credits/properties), or `nil` if absent or a
  /// different shape.
  func objectArrayField(_ key: String) -> [[String: String]]? {
    if case .objectArray(let value)? = fields[key] { return value }
    return nil
  }
}

/// Reads/writes the caller's in-flight edit session for a given record type. catalog-web is the
/// primary writer of this store (catalog-api only reads it at finalize time and deletes it once
/// finalize completes, plus one exception for pull-back - see catalog-api's own
/// `editsession` package doc comment).
struct EditSessionStore {
  let request: Request

  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }()

  private static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()

  private func key(userID: String, recordType: String) -> RedisKey {
    RedisKey("edit-session:\(userID):\(recordType)")
  }

  /// Fetches the caller's in-flight session for `recordType`, or `nil` if none exists or Redis
  /// isn't configured (fails open, same contract as `SessionUserAccess`'s read).
  func get(userID: String, recordType: String) async -> EditSession? {
    await withSpan("edit-session-get") { _ in
      guard request.application.editSessionRedisConfigured else { return nil }

      guard
        let raw = try? await request.redis(.editSession).get(
          key(userID: userID, recordType: recordType), as: String.self
        ).get(),
        let data = raw.data(using: .utf8),
        let session = try? Self.decoder.decode(EditSession.self, from: data)
      else { return nil }

      return session
    }
  }

  /// Writes `session` for the caller's `recordType`, overwriting any existing one. Throws if
  /// Redis isn't configured or the write fails - unlike reads, a session write is a user-visible
  /// action ("start editing") that must not silently no-op.
  func set(userID: String, recordType: String, session: EditSession) async throws {
    try await withSpan("edit-session-set") { _ in
      guard request.application.editSessionRedisConfigured else {
        throw Abort(.serviceUnavailable, reason: "Edit sessions are not configured")
      }
      let data = try Self.encoder.encode(session)
      guard let json = String(data: data, encoding: .utf8) else {
        throw Abort(.internalServerError, reason: "Failed to encode edit session")
      }
      _ = try await request.redis(.editSession).set(
        key(userID: userID, recordType: recordType), to: json
      ).get()
    }
  }

  /// Deletes the caller's in-flight session for `recordType` - a missing session is not an
  /// error (discarding an already-expired/finalized session is a normal, successful outcome).
  func delete(userID: String, recordType: String) async {
    await withSpan("delete-session") { _ in
      guard request.application.editSessionRedisConfigured else { return }
      _ = try? await request.redis(.editSession).delete(
        key(userID: userID, recordType: recordType)
      ).get()
    }
  }
}

extension Request {
  var editSessions: EditSessionStore { EditSessionStore(request: self) }
}

extension Application {
  private struct EditSessionRedisConfiguredKey: StorageKey {
    typealias Value = Bool
  }

  /// Whether the `.editSession` Redis connection (`REDIS_DB=2` on catalog-api's own instance)
  /// is configured - a separate flag from `redisConfigured`/`sharedSessionRedisConfigured`,
  /// which track this app's own cache Redis and the shared auth session Redis respectively.
  var editSessionRedisConfigured: Bool {
    get { storage[EditSessionRedisConfiguredKey.self] ?? false }
    set { storage[EditSessionRedisConfiguredKey.self] = newValue }
  }
}
