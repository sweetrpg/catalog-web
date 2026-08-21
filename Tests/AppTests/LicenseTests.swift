import AdminAPIClient
import CatalogAPIClient
import Foundation
import Redis
import Testing
import VaporTesting

@testable import App

@Suite("License")
struct LicenseTests {
  @Test("license edit page renders correct field kinds, with long-text fields last")
  func licenseEditPageRendersFieldKindsAndOrder() async throws {
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-license-edit") { req async throws -> View in
        let user = SessionUser(
          sub: "abc", name: "Editor", email: nil, roles: ["editor"], accessToken: "test-token",
          expiry: Date().addingTimeInterval(3600))
        let base = makeEditContext(
          id: "1", basePath: "/licenses", fields: licenseFields,
          values: [
            "title": "CC BY 4.0", "status": "Accepted", "availability": "Released",
            "deed": "Full deed text", "legal_code": "Full legal text",
          ],
          user: user, meta: await PageMeta.make(req))
        return try await req.view.render(
          "licenses/edit",
          LicenseEditContext(
            base: base, tags: [], tagOptions: [], canAddTag: false, canManageVolumes: false,
            selectedVolumes: [], allVolumes: []))
      }
      try await app.testing().test(.GET, "test-license-edit") { res in
        #expect(res.status == .ok)
        let body = res.body.string
        #expect(body.contains(#"<textarea class="input" id="deed""#))
        #expect(body.contains(#"<textarea class="input" id="legal_code""#))
        #expect(body.contains(#"<select class="input" id="status""#))
        #expect(body.contains(#"<option value="Accepted"  selected >"#))
        #expect(body.contains(#"<select class="input" id="availability""#))
        #expect(body.contains(#"<option value="Released"  selected >"#))
        // deed/legal_code render after notes, not before website/status/availability.
        let notesIndex = body.range(of: #"id="notes""#)
        let deedIndex = body.range(of: #"id="deed""#)
        #expect(notesIndex != nil && deedIndex != nil)
        if let notesIndex, let deedIndex {
          #expect(notesIndex.lowerBound < deedIndex.lowerBound)
        }
      }
    }
  }
}
