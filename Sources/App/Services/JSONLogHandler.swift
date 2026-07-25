import Foundation
import Logging

/// Structured JSON logging, matching the Go services' convention (`common.go/logging`, per
/// docs/service-conventions.md) of structured, level-aware logs rather than plain text - so log
/// aggregation (whatever ingests the Go services' JSON logs) can parse this app's logs the same
/// way. One JSON object per line to stdout.
struct JSONLogHandler: LogHandler {
  var metadata: Logger.Metadata = [:]
  var logLevel: Logger.Level = .info
  let label: String

  subscript(metadataKey key: String) -> Logger.Metadata.Value? {
    get { metadata[key] }
    set { metadata[key] = newValue }
  }

  func log(
    level: Logger.Level,
    message: Logger.Message,
    metadata explicitMetadata: Logger.Metadata?,
    source: String,
    file: String,
    function: String,
    line: UInt
  ) {
    var entry: [String: Any] = [
      "timestamp": ISO8601DateFormatter().string(from: Date()),
      "level": level.rawValue,
      "logger": label,
      "message": message.description,
    ]

    let merged = self.metadata.merging(explicitMetadata ?? [:]) { _, new in new }
    for (key, value) in merged {
      entry[key] = Self.jsonValue(value)
    }

    guard let data = try? JSONSerialization.data(withJSONObject: entry),
      let line = String(data: data, encoding: .utf8)
    else {
      print(entry)
      return
    }
    print(line)
  }

  private static func jsonValue(_ value: Logger.MetadataValue) -> Any {
    switch value {
    case .string(let s): return s
    case .stringConvertible(let s): return s.description
    case .array(let a): return a.map(jsonValue)
    case .dictionary(let d): return d.mapValues(jsonValue)
    }
  }
}

extension LoggingSystem {
  static func bootstrapJSON(minimumLevel: Logger.Level) {
    self.bootstrap { label in
      var handler = JSONLogHandler(label: label)
      handler.logLevel = minimumLevel
      return handler
    }
  }
}
