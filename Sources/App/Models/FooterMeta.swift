import Foundation
import Vapor

/// Values for the standard three-line footer (`standard-site-footer`): the current year, the
/// build version label, and the legal links. The links hang off the app's root URL setting and
/// never its path prefix, because `main-web` serves `/terms`, `/privacy` and `/support` at the
/// site root and `<prefix>/terms` would 404.
struct FooterMeta: Content {
  let year: String
  let versionLabel: String
  let termsURL: String
  let privacyURL: String
  let supportURL: String

  init(rootURL: String, version: String, now: Date = Date()) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    self.year = String(calendar.component(.year, from: now))
    // Release versions are bare ("0.28.0"); "dev" outside a container is left as is.
    self.versionLabel = version.first?.isNumber == true ? "v\(version)" : version
    let root = rootURL.hasSuffix("/") ? rootURL : rootURL + "/"
    self.termsURL = root + "terms"
    self.privacyURL = root + "privacy"
    self.supportURL = root + "support"
  }
}
