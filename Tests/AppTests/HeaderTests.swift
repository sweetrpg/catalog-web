import AdminAPIClient
import CatalogAPIClient
import Foundation
import Redis
import Testing
import VaporTesting

@testable import App

@Suite("Header")
struct HeaderTests {

  // Renders a real Leaf template (not just a Swift-side compile check, since Leaf resolves
  // `#(meta.loginURL)` dynamically at render time) to confirm the header partial's login/logout
  // links interpolate correctly.

  @Test("header renders the log-in link when logged out")
  func headerRendersLogInLink() async throws {
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-home") { req async throws -> View in
        try await req.view.render(
          "home",
          HomeContext(
            statCards: [], tagCloud: [], user: nil,
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-home") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains(#"href="/auth/login?return_to=/test-home""#))
        #expect(!res.body.string.contains("Log Out"))
        // The avatar menu is always present (mystery-man icon + a Log in item), not hidden
        // when logged out - see feat/avatar-menu-always-present-and-theme.
        #expect(res.body.string.contains("avatar-menu-trigger"))
        #expect(res.body.string.contains("mystery-man.svg"))
      }
    }
  }

  @Test("header renders the avatar menu without Admin for a non-admin session")
  func headerRendersAvatarMenuWithoutAdminForNonAdmin() async throws {
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-home") { req async throws -> View in
        try await req.view.render(
          "home",
          HomeContext(
            statCards: [], tagCloud: [],
            user: LeafUser(
              SessionUser(
                sub: "abc", name: "Alice", email: nil, roles: [], accessToken: "test-token",
                expiry: Date().addingTimeInterval(3600))),
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-home") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains("avatar-menu-trigger"))
        #expect(res.body.string.contains(#"href="/users""#))
        #expect(!res.body.string.contains(#"href="/admin""#))
        #expect(res.body.string.contains("avatar-menu-item-danger"))
        #expect(res.body.string.contains(#"action="/auth/logout?return_to=/test-home""#))
      }
    }
  }

  @Test("header renders the app switcher with four destinations and no admin link")
  func headerRendersAppSwitcher() async throws {
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-home") { req async throws -> View in
        try await req.view.render(
          "home",
          HomeContext(
            statCards: [], tagCloud: [], user: nil,
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-home") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains("app-switcher-trigger"))
        #expect(res.body.string.contains(#"href="/">Main"#))
        #expect(res.body.string.contains(#"href="/catalog">Catalog"#))
        #expect(res.body.string.contains(#"href="/shelf">Shelf"#))
        #expect(res.body.string.contains(#"href="/initiative">Initiative"#))
        #expect(!res.body.string.contains(#"app-switcher-item" href="/admin""#))
      }
    }
  }

  @Test("header renders a Gravatar image with an onerror fallback when the session has an email")
  func headerRendersGravatarImageWhenEmailPresent() async throws {
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-home") { req async throws -> View in
        try await req.view.render(
          "home",
          HomeContext(
            statCards: [], tagCloud: [],
            user: LeafUser(
              SessionUser(
                sub: "abc", name: "Alice", email: "alice@example.com", roles: [],
                accessToken: "test-token", expiry: Date().addingTimeInterval(3600))),
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-home") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains("avatar-menu-avatar"))
        #expect(res.body.string.contains("https://www.gravatar.com/avatar/"))
        #expect(res.body.string.contains("d=404"))
        #expect(res.body.string.contains(#"onload="this.nextElementSibling.style.display='none'""#))
        #expect(res.body.string.contains(#"onerror="this.style.display='none'""#))
        #expect(res.body.string.contains("avatar-menu-fallback"))
      }
    }
  }

  @Test("header renders only the fallback letter when the session has no email")
  func headerRendersOnlyFallbackWithoutEmail() async throws {
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-home") { req async throws -> View in
        try await req.view.render(
          "home",
          HomeContext(
            statCards: [], tagCloud: [],
            user: LeafUser(
              SessionUser(
                sub: "abc", name: "Alice", email: nil, roles: [], accessToken: "test-token",
                expiry: Date().addingTimeInterval(3600))),
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-home") { res in
        #expect(res.status == .ok)
        #expect(!res.body.string.contains("avatar-menu-avatar"))
        #expect(res.body.string.contains("avatar-menu-fallback"))
      }
    }
  }

  @Test("header renders the Admin link for an admin session")
  func headerRendersAdminLinkForAdminSession() async throws {
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-home") { req async throws -> View in
        try await req.view.render(
          "home",
          HomeContext(
            statCards: [], tagCloud: [],
            user: LeafUser(
              SessionUser(
                sub: "abc", name: "Bob", email: nil, roles: ["admin"], accessToken: "test-token",
                expiry: Date().addingTimeInterval(3600))),
            meta: await PageMeta.make(req)))
      }
      try await app.testing().test(.GET, "test-home") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains(#"href="/admin""#))
        #expect(res.body.string.contains(#"href="/users""#))
      }
    }
  }
}
