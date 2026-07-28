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
  let banners: [Banner]

  /// Fetches banner messages as part of building page metadata, so every existing call site
  /// (`meta: PageMeta(req)` -> `meta: await PageMeta.make(req)`) gets banner display "for
  /// free" without each controller needing its own admin-api call. Async because fetching
  /// banners is (unlike every other field here) a network call - see AdminClient.
  static func make(_ req: Request) async -> PageMeta {
    let pageScope = "page:\(req.basePath)\(req.url.path)"
    let banners = await req.adminClient.fetchBanners(
      scopes: ["platform", "service:catalog", pageScope])
    return PageMeta(
      basePath: req.basePath,
      rootURL: req.rootURL,
      sharedAssetsURL: req.sharedAssetsURL,
      buildVersion: req.buildInfo.version,
      buildDate: req.buildInfo.date,
      banners: banners
    )
  }
}
