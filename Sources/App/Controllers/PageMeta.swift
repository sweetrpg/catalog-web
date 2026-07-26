import Vapor

/// Bundles the per-request values every page's template needs regardless of what the page is
/// actually about - the path prefix for internal links (see AppPaths.swift) and the build
/// version/date shown in the footer. One field on every page Context instead of duplicating
/// both across each of them.
struct PageMeta: Content {
  let basePath: String
  let rootURL: String
  let sharedAssetsURL: String
  let buildVersion: String
  let buildDate: String

  init(_ req: Request) {
    self.basePath = req.basePath
    self.rootURL = req.rootURL
    self.sharedAssetsURL = req.sharedAssetsURL
    self.buildVersion = req.buildInfo.version
    self.buildDate = req.buildInfo.date
  }
}
