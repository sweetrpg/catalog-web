import Crypto
import Foundation
import Vapor

/// Home, Browse, and Volume Detail - the three catalog-browsing pages, all backed by
/// catalog-api. Grouped in one controller since they share the same volume-fetching path,
/// unlike ShelvesController, which has its own concern.
struct CatalogController: RouteCollection {
  func boot(routes: RoutesBuilder) throws {
    routes.get(use: home)
    routes.get("browse", use: browse)
    routes.get("volumes", ":volumeID", use: detail)
  }

  @Sendable
  func home(req: Request) async throws -> View {
    let volumes = try await req.catalogAPI.fetchVolumes()
    let trending = Array(volumes.prefix(8))
    let tagCloud = Array(Set(volumes.flatMap(\.tags))).sorted().prefix(14)

    return try await req.view.render(
      "home",
      HomeContext(
        volumeCount: volumes.count,
        trending: trending.map(LeafVolumeCard.init),
        tagCloud: tagCloud.map { LeafTag(name: $0) },
        user: (await req.currentUser).map(LeafUser.init),
        meta: await PageMeta.make(req)
      ))
  }

  @Sendable
  func browse(req: Request) async throws -> View {
    struct Query: Content {
      let q: String?
      let tag: String?
    }
    let query = try req.query.decode(Query.self)
    let volumes = try await req.catalogAPI.fetchVolumes()
    let tagCloud = Array(Set(volumes.flatMap(\.tags))).sorted().prefix(14)

    let filtered = volumes.filter { volume in
      if let tag = query.tag, !tag.isEmpty, !volume.tags.contains(tag) { return false }
      guard let q = query.q, !q.isEmpty else { return true }
      let needle = q.lowercased()
      return volume.title.lowercased().contains(needle)
        || volume.description.lowercased().contains(needle)
        || volume.tags.contains { $0.lowercased().contains(needle) }
    }

    return try await req.view.render(
      "browse",
      BrowseContext(
        query: query.q ?? "",
        noActiveTag: query.tag == nil || query.tag!.isEmpty,
        tagCloud: tagCloud.map { LeafTag(name: $0, isActive: $0 == query.tag) },
        volumes: filtered.map(LeafVolumeCard.init),
        noResults: filtered.isEmpty,
        user: (await req.currentUser).map(LeafUser.init),
        meta: await PageMeta.make(req)
      ))
  }

  @Sendable
  func detail(req: Request) async throws -> View {
    guard let volumeID = req.parameters.get("volumeID") else {
      throw Abort(.badRequest)
    }
    let volumes = try await req.catalogAPI.fetchVolumes()
    guard var volume = await req.catalogAPI.fetchVolume(id: volumeID, allVolumes: volumes)
    else {
      throw Abort(.notFound)
    }
    volume.credits = try await req.catalogAPI.fetchCredits(volumeID: volumeID)
    volume.reviews = try await req.catalogAPI.fetchReviews(volumeID: volumeID)

    return try await req.view.render(
      "detail",
      DetailContext(
        volume: LeafVolumeDetail(volume),
        user: (await req.currentUser).map(LeafUser.init),
        meta: await PageMeta.make(req)
      ))
  }
}

// MARK: - Leaf page contexts

/// Concrete, per-page Encodable structs - not `[String: Encodable]` dictionaries. Swift's
/// `Dictionary` only conditionally conforms to `Encodable` when its `Value` is *concretely*
/// `Encodable`; `any Encodable` as the value type doesn't satisfy that, so a dictionary typed
/// `[String: Encodable]` does not itself conform to `Encodable` and can't be passed to
/// `req.view.render`, which requires a real `Encodable` context type.

struct HomeContext: Content {
  let volumeCount: Int
  let trending: [LeafVolumeCard]
  let tagCloud: [LeafTag]
  let user: LeafUser?
  let meta: PageMeta
}

struct BrowseContext: Content {
  let query: String
  let noActiveTag: Bool
  let tagCloud: [LeafTag]
  let volumes: [LeafVolumeCard]
  let noResults: Bool
  let user: LeafUser?
  let meta: PageMeta
}

struct DetailContext: Content {
  let volume: LeafVolumeDetail
  let user: LeafUser?
  let meta: PageMeta
}

// MARK: - Leaf view models

/// Flat, Leaf-friendly wrappers around the domain models above. Kept separate from
/// `VolumeViewModel` etc. so the API-facing models don't accumulate template-only convenience
/// properties (`ratingStars`, `hasX` booleans) that have nothing to do with fetching data.

struct LeafTag: Content {
  let name: String
  var isActive: Bool = false
}

struct LeafUser: Content {
  let name: String
  /// First character of `name`, uppercased - the avatar trigger's label.
  let avatarInitial: String
  /// Gravatar image URL derived from the session's email (`d=404` so a visitor with no
  /// Gravatar gets a real 404 rather than Gravatar's generic mystery-person image) - the
  /// shared avatar-menu markup's `onerror` falls back to `avatarInitial` on load failure.
  /// `nil` when the session has no email.
  let avatarGravatarURL: String?
  /// `true` when the session's `roles` (verified by `users-api`) includes `admin` - gates the
  /// avatar menu's "Admin" item, mirroring `admin-web`'s own `AuthRequiredMiddleware` role
  /// check.
  let isAdmin: Bool

  init(_ user: SessionUser) {
    self.name = user.name
    self.avatarInitial = user.name.first.map { String($0).uppercased() } ?? ""
    self.avatarGravatarURL = user.email.map { email in
      let canonical = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      let hash = Insecure.MD5.hash(data: Data(canonical.utf8))
        .map { String(format: "%02x", $0) }
        .joined()
      return "https://www.gravatar.com/avatar/\(hash)?s=64&d=404"
    }
    self.isAdmin = user.roles.contains("admin")
  }
}

struct LeafVolumeCard: Content {
  let id: String
  let title: String
  let tagChips: [String]
  let coverAssetPath: String

  init(_ volume: VolumeViewModel) {
    self.id = volume.id
    self.title = volume.title
    self.tagChips = volume.tagChips
    self.coverAssetPath = volume.coverAssetPath
  }
}

struct LeafVolumeDetail: Content {
  let id: String
  let title: String
  let description: String
  let hasDescription: Bool
  let notes: String
  let hasNotes: Bool
  let tags: [String]
  let systemNames: [String]
  let hasSystemNames: Bool
  let publisherNames: [String]
  let hasPublisherNames: Bool
  let studioNames: [String]
  let hasStudioNames: Bool
  let licenseNames: [String]
  let hasLicenseNames: Bool
  let credits: [LeafCredit]
  let hasCredits: Bool
  let reviews: [LeafReview]
  let hasReviews: Bool
  let coverAssetPath: String

  init(_ volume: VolumeViewModel) {
    self.id = volume.id
    self.title = volume.title
    self.description = volume.description
    self.hasDescription = !volume.description.isEmpty
    self.notes = volume.notes
    self.hasNotes = !volume.notes.isEmpty
    self.tags = volume.tags
    self.systemNames = volume.systemNames
    self.hasSystemNames = !volume.systemNames.isEmpty
    self.publisherNames = volume.publisherNames
    self.hasPublisherNames = !volume.publisherNames.isEmpty
    self.studioNames = volume.studioNames
    self.hasStudioNames = !volume.studioNames.isEmpty
    self.licenseNames = volume.licenseNames
    self.hasLicenseNames = !volume.licenseNames.isEmpty
    self.credits = volume.credits.map(LeafCredit.init)
    self.hasCredits = !volume.credits.isEmpty
    self.reviews = volume.reviews.map(LeafReview.init)
    self.hasReviews = !volume.reviews.isEmpty
    self.coverAssetPath = volume.coverAssetPath
  }
}

struct LeafCredit: Content {
  let role: String
  let person: String

  init(_ credit: (role: String, person: String)) {
    self.role = credit.role
    self.person = credit.person
  }
}

struct LeafReview: Content {
  let author: String
  let starsLabel: String
  let text: String

  init(_ review: (author: String, rating: Int, text: String)) {
    self.author = review.author
    self.starsLabel =
      String(repeating: "\u{2605}", count: max(0, min(5, review.rating)))
      + String(repeating: "\u{2606}", count: max(0, 5 - review.rating))
    self.text = review.text
  }
}
