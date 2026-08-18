import CatalogAPIClient
import Crypto
import Foundation
import Vapor

struct LeafUser: Content {
  let name: String
  /// Shown as a smaller, muted subtitle line under `name` in the avatar menu. `nil` when the
  /// session has no email (same source as `avatarGravatarURL` below).
  let email: String?
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
    self.email = user.email
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
