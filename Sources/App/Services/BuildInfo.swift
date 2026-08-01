import Foundation
import Vapor

/// Read from the JSON file the Dockerfile bakes in at build time (same `BUILD_INFO_PATH`
/// convention as the Go services - see docs/service-conventions.md), not generated at runtime:
/// this app has no build-time code generation step of its own to inject a version constant, so
/// a file written during the Docker build is the simplest way to surface it. Falls back to
/// placeholder values when the file doesn't exist (local `swift run`, outside a container).
struct BuildInfo: Content {
  let version: String
  let date: String
  let sha: String

  private struct RawBuildInfo: Decodable {
    let version: String
    let date: String
    let sha: String
  }

  static func load() -> BuildInfo {
    let path = Environment.get("BUILD_INFO_PATH") ?? "/app/config/build-info.json"
    guard let data = FileManager.default.contents(atPath: path),
      let raw = try? JSONDecoder().decode(RawBuildInfo.self, from: data)
    else {
      return BuildInfo(version: "dev", date: "unknown", sha: "unset")
    }
    return BuildInfo(version: raw.version, date: raw.date, sha: raw.sha)
  }
}

extension Application {
  private struct BuildInfoKey: StorageKey {
    typealias Value = BuildInfo
  }

  var buildInfo: BuildInfo {
    get {
      guard let info = storage[BuildInfoKey.self] else {
        let info = BuildInfo.load()
        storage[BuildInfoKey.self] = info
        return info
      }
      return info
    }
    set { storage[BuildInfoKey.self] = newValue }
  }
}

extension Request {
  var buildInfo: BuildInfo { application.buildInfo }
}
