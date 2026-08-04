import Vapor

/// Bundles the per-request values every page's template needs regardless of what the page is
/// actually about - the path prefix for internal links (see AppPaths.swift), the build
/// version/date shown in the footer, and any active banner messages. One field on every page
/// Context instead of duplicating all of this across each of them.
struct PageMeta: Content {
  let basePath: String
  let rootURL: String
  let sharedAssetsURL: String
  let buildVersion: String
  let buildDate: String
  let buildHash: String
  let banners: [LeafBanner]
  /// `auth-web`'s login link, with `return_to` set to this request's own full path (including
  /// `basePath`) so a successful login lands the visitor back where they started. `auth-web`
  /// sits at `/auth` on the same host root, not under this app's own `basePath` - see
  /// design.md's "auth-web is the sole owner of the Authorization Code exchange" decision.
  let loginURL: String
  let logoutURL: String
  /// Fixed paths on the shared `dev.sweetrpg.com` host, matching `/catalog`'s own convention -
  /// see design.md's "User Settings links to a fixed, currently-unbuilt path" decision in the
  /// suite-avatar-menu OpenSpec change. `adminURL` gates behind `LeafUser.isAdmin` in the
  /// template; `userSettingsURL` (`/users`) 404s until `users-web` ships - a separate,
  /// already-tracked gap.
  let adminURL: String
  let userSettingsURL: String

  /// Fetches banner messages as part of building page metadata, so every existing call site
  /// (`meta: PageMeta(req)` -> `meta: await PageMeta.make(req)`) gets banner display "for
  /// free" without each controller needing its own admin-api call. Async because fetching
  /// banners is (unlike every other field here) a network call - see AdminClient.
  static func make(_ req: Request) async -> PageMeta {
    let pageScope = "page:\(req.basePath)\(req.url.path)"
    let banners = await req.adminClient.fetchBanners(
      scopes: ["platform", "service:catalog", pageScope]
    ).map(LeafBanner.init)
    let returnTo = "\(req.basePath)\(req.url.path)"
    let encodedReturnTo =
      returnTo.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "/"
    return PageMeta(
      basePath: req.basePath,
      rootURL: req.rootURL,
      sharedAssetsURL: req.sharedAssetsURL,
      buildVersion: req.buildInfo.version,
      buildDate: req.buildInfo.date,
      buildHash: String(req.buildInfo.sha.prefix(8)),
      banners: banners,
      loginURL: "/auth/login?return_to=\(encodedReturnTo)",
      logoutURL: "/auth/logout",
      adminURL: "/admin",
      userSettingsURL: "/users"
    )
  }
}
