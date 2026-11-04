import Foundation
import Testing
import VaporTesting

@testable import App

private struct FooterContext: Content {
  let meta: PageMeta
}

@Suite("Standard site footer", .serialized)
struct SiteFooterTests {
  private func render() async throws -> (html: String, meta: PageMeta) {
    var html = ""
    var meta: PageMeta?
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-footer") { req async throws -> View in
        let page = await PageMeta.make(req)
        meta = page
        return try await req.view.render("partials/footer", FooterContext(meta: page))
      }
      try await app.testing().test(.GET, "test-footer") { html = $0.body.string }
    }
    return (html, try #require(meta))
  }

  @Test("renders the three lines in order, the last also marked as the build line")
  func threeLinesInOrder() async throws {
    let (html, _) = try await render()
    let copyright = try #require(html.range(of: "Pilgrimage Software"))
    let terms = try #require(html.range(of: "Terms of Service"))
    let build = try #require(html.range(of: "footer-line footer-build"))
    #expect(copyright.lowerBound < terms.lowerBound && terms.lowerBound < build.lowerBound)
    #expect(html.components(separatedBy: "class=\"footer-line").count - 1 == 3)
    #expect(html.contains("Privacy Policy") && html.contains("Support"))
    #expect(html.contains("built unknown / unset"))
  }

  @Test("the copyright shows the current year, not a literal")
  func currentYear() async throws {
    let (html, _) = try await render()
    let year = Calendar(identifier: .gregorian).component(.year, from: Date())
    #expect(html.contains("&copy; \(year) Pilgrimage Software"))
  }

  @Test("legal links come from the root URL and never include the app's path prefix")
  func linksIgnorePrefix() async throws {
    let (html, meta) = try await render()
    let root = meta.rootURL.hasSuffix("/") ? meta.rootURL : meta.rootURL + "/"
    #expect(meta.footer.termsURL == root + "terms")
    #expect(html.contains("href=\"\(root)terms\""))
    #expect(html.contains("href=\"\(root)privacy\""))
    #expect(html.contains("href=\"\(root)support\""))
    if !meta.basePath.isEmpty { #expect(!html.contains("\(meta.basePath)/terms")) }
  }

  @Test("release versions get a v prefix; dev is left alone")
  func versionLabel() {
    #expect(FooterMeta(rootURL: "/", version: "0.28.0").versionLabel == "v0.28.0")
    #expect(FooterMeta(rootURL: "/", version: "dev").versionLabel == "dev")
    #expect(
      FooterMeta(rootURL: "https://dev.sweetrpg.com", version: "1").supportURL
        == "https://dev.sweetrpg.com/support")
  }
}
