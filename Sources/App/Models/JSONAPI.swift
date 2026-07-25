import Foundation

/// Minimal JSON:API envelope, matching catalog-api's response shape closely enough to decode
/// the fields this app actually uses. Not a general-purpose JSON:API client - extend as new
/// endpoints are wired up rather than trying to model the whole spec up front.
struct JSONAPIDocument<Attributes: Codable & Sendable>: Codable, Sendable {
  struct Resource: Codable, Sendable {
    let id: String
    let type: String
    let attributes: Attributes
    let relationships: [String: JSONAPIRelationship]?
  }

  let data: [Resource]
}

struct JSONAPISingleDocument<Attributes: Codable & Sendable>: Codable, Sendable {
  struct Resource: Codable, Sendable {
    let id: String
    let type: String
    let attributes: Attributes
    let relationships: [String: JSONAPIRelationship]?
  }

  let data: Resource
}

struct JSONAPIRelationship: Codable, Sendable {
  let data: JSONAPIRelationshipData?
}

/// Relationship `data` is either a single identifier object or an array of them (to-one vs.
/// to-many) - JSON:API allows both shapes depending on the relationship, so this decodes
/// whichever is present rather than assuming one.
enum JSONAPIRelationshipData: Codable, Sendable {
  case single(ResourceIdentifier)
  case many([ResourceIdentifier])

  struct ResourceIdentifier: Codable, Sendable {
    let id: String
    let type: String
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let many = try? container.decode([ResourceIdentifier].self) {
      self = .many(many)
    } else {
      self = .single(try container.decode(ResourceIdentifier.self))
    }
  }

  var ids: [String] {
    switch self {
    case .single(let identifier): return [identifier.id]
    case .many(let identifiers): return identifiers.map(\.id)
    }
  }
}
