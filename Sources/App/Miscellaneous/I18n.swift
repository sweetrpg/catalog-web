import Foundation
import Vapor

/// Loads the flat dotted-key locale tables from `Resources/Localizations/<code>.json` at
/// startup and resolves each request's locale: `locale` cookie override, then the first tag of
/// the `Accept-Language` header's base subtag, then English. Templates read translations via
/// `#(meta.l10n.<page>.<key>)` (see `PageMeta.l10n`). Part of the platform-wide localization
/// contract - see sweetrpg/platform OpenSpec change `full-localization-web-apps`.
///
/// Deliberately session-free: LingoVapor's own `Request.locale` reads session data and crashes
/// on any app that never registers `SessionsMiddleware` (this one doesn't - see
/// configure.swift), so resolution parses the cookie/header directly instead.
enum I18n {
  nonisolated(unsafe) static var tables: [String: [String: String]] = [:]
  static let defaultLocale = "en"

  static func loadTables() throws {
    let dir = URL(fileURLWithPath: "Resources/Localizations")
    let urls = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "json" }
    var loaded: [String: [String: String]] = [:]
    for url in urls {
      let data = try Data(contentsOf: url)
      // Values here are plain strings; Lingo's CLDR-plural entries (e.g.
      // catalog.volume_count) are nested {one,other} objects consumed only through
      // lingo.localize, so anything non-string is skipped rather than fatal.
      let raw = try JSONSerialization.jsonObject(with: data)
      guard let entries = raw as? [String: Any] else { continue }
      loaded[url.deletingPathExtension().lastPathComponent] =
        entries.compactMapValues { $0 as? String }
    }
    tables = loaded
  }

  static func resolveLocale(for request: Request) -> String {
    if let candidate = candidateLocaleCode(for: request), tables[candidate] != nil {
      return candidate
    }
    return defaultLocale
  }

  /// Resolves the locale that governs number formatting (grouping separators) for a request -
  /// same sources and order as `resolveLocale` (`locale` cookie override, then the
  /// `Accept-Language` base subtag, then English), but without the on-disk-table gate: numbers
  /// should follow the browser's declared language even before a translation table exists for
  /// it. Only a well-formed 2/3-letter code is honored; anything else (an `*` q-value, a garbage
  /// cookie value) falls back to English rather than handing `NumberFormatter` a junk identifier.
  static func numberLocale(for request: Request) -> Locale {
    if let candidate = candidateLocaleCode(for: request),
      candidate.count == 2 || candidate.count == 3, candidate.allSatisfy(\.isLetter)
    {
      return Locale(identifier: candidate)
    }
    return Locale(identifier: defaultLocale)
  }

  /// First `locale`-cookie value, else the first `Accept-Language` tag's base subtag, else nil
  /// (an absent header). No table-membership or well-formedness check here - each caller gates
  /// on its own contract (`resolveLocale` on table presence, `numberLocale` on code shape).
  private static func candidateLocaleCode(for request: Request) -> String? {
    if let cookie = request.cookies["locale"]?.string, !cookie.isEmpty { return cookie }
    guard let header = request.headers.first(name: .acceptLanguage) else { return nil }
    let tag = header.split(separator: ",").first.map(String.init) ?? ""
    let stripped = tag.split(separator: ";").first.map(String.init) ?? ""
    let base = stripped.split(separator: "-").first.map(String.init) ?? ""
    return base.isEmpty ? nil : base
  }

  /// Flat key -> string for this request, with English filling any gap in a non-English table.
  /// Falls back to lazy loading because test helpers (VaporTesting's closure-form `withApp`)
  /// never run `configure`, where the eager `loadTables()` happens.
  static func table(for request: Request) -> [String: String] {
    if tables.isEmpty { try? loadTables() }
    let locale = resolveLocale(for: request)
    guard locale != defaultLocale, let overlay = tables[locale] else {
      return tables[defaultLocale] ?? [:]
    }
    var merged = tables[defaultLocale] ?? [:]
    merged.merge(overlay) { _, localized in localized }
    return merged
  }

  /// Regroups the flat table two levels deep - `"common.cancel"` becomes
  /// `["common": ["cancel": ...]]` - so Leaf's dot-path resolution can walk it as
  /// `#(meta.l10n.common.cancel)`. Keys with more than one dot keep their remainder intact
  /// (`common.viewing_proposal_from` stays one key under `common`).
  static func nested(_ table: [String: String]) -> [String: [String: String]] {
    var result: [String: [String: String]] = [:]
    for (key, value) in table {
      let parts = key.split(separator: ".", maxSplits: 1).map(String.init)
      guard parts.count == 2 else { continue }
      result[parts[0], default: [:]][parts[1]] = value
    }
    return result
  }
}
