import Foundation
import Vapor

extension Request {
  private static let sessionKey = "user"

  var currentUser: SessionUser? {
    get {
      guard let json = session.data[Self.sessionKey],
        let data = json.data(using: .utf8)
      else { return nil }
      return try? JSONDecoder().decode(SessionUser.self, from: data)
    }
    set {
      guard let newValue,
        let data = try? JSONEncoder().encode(newValue),
        let json = String(data: data, encoding: .utf8)
      else {
        session.data[Self.sessionKey] = nil
        return
      }
      session.data[Self.sessionKey] = json
    }
  }
}
