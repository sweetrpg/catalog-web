import Foundation
import Testing
import VaporTesting

@testable import App

@Suite("GameRoomAPIClient")
struct GameRoomAPIClientTests {
  // game-room-api's HTTP client isn't interceptable by VaporTesting's in-memory transport, so
  // these bind a stand-in game-room-api on a fixed port - same pattern as
  // VolumeScopedFetchTests.withFakeCatalogAPI.

  @discardableResult
  private func withFakeGameRoomAPI<T>(
    port: Int, configure: (Application) -> Void, body: (Application) async throws -> T
  ) async throws -> T {
    let fake = try await Application.make(Environment(name: "testing", arguments: ["vapor"]))
    fake.http.server.configuration.hostname = "127.0.0.1"
    fake.http.server.configuration.port = port
    configure(fake)
    do {
      try await fake.startup()
    } catch {
      try? await fake.asyncShutdown()
      throw error
    }
    defer { Task { try? await fake.asyncShutdown() } }
    return try await withApp { app in
      app.backendConfig = BackendConfig(
        catalogAPIURL: "unused", gameSystemsAPIURL: "unused", profilesAPIURL: "unused",
        gameRoomAPIURL: "http://127.0.0.1:\(port)", adminAPIURL: nil, volumeTagsLimit: 20)
      return try await body(app)
    }
  }

  private func libraryJSON(_ entries: [String]) -> String {
    let encoded = entries.map {
      #"{"volume_id": "\#($0)", "volume_title": "", "added_at": "2024-01-01T00:00:00Z"}"#
    }.joined(separator: ",")
    return
      #"{"id": "lib-1", "user_id": "u1", "default_visibility": "private", "entries": [\#(encoded)]}"#
  }

  @Test("isInLibrary returns true when the volume is among the entries")
  func isInLibraryPresent() async throws {
    try await withFakeGameRoomAPI(
      port: 18_791,
      configure: { fake in
        fake.get("users", ":userID", "library") { _ in
          Response(
            status: .ok, headers: ["content-type": "application/json"],
            body: .init(string: self.libraryJSON(["v1", "v2"])))
        }
      },
      body: { app in
        app.get("test") { req async throws -> String in
          try await req.gameRoomAPI.isInLibrary(userID: "u1", volumeID: "v1", token: "tok")
            ? "present" : "absent"
        }
        try await app.testing().test(.GET, "test") { res in
          #expect(res.status == .ok)
          #expect(res.body.string == "present")
        }
      })
  }

  @Test("isInLibrary returns false when the volume is absent from the entries")
  func isInLibraryAbsent() async throws {
    try await withFakeGameRoomAPI(
      port: 18_792,
      configure: { fake in
        fake.get("users", ":userID", "library") { _ in
          Response(
            status: .ok, headers: ["content-type": "application/json"],
            body: .init(string: self.libraryJSON(["v2"])))
        }
      },
      body: { app in
        app.get("test") { req async throws -> String in
          try await req.gameRoomAPI.isInLibrary(userID: "u1", volumeID: "v1", token: "tok")
            ? "present" : "absent"
        }
        try await app.testing().test(.GET, "test") { res in
          #expect(res.status == .ok)
          #expect(res.body.string == "absent")
        }
      })
  }

  @Test("isInLibrary returns false for a brand-new user with no library yet")
  func isInLibraryNewUser() async throws {
    // game-room-api's GET /users/:user_id/library always returns 200 with a synthesized empty
    // library for a user who has never had one (it doesn't 404) - so "doesn't exist yet" and
    // "exists but empty" are the same wire shape, and both read as "not in library" here.
    try await withFakeGameRoomAPI(
      port: 18_793,
      configure: { fake in
        fake.get("users", ":userID", "library") { _ in
          Response(
            status: .ok, headers: ["content-type": "application/json"],
            body: .init(string: self.libraryJSON([])))
        }
      },
      body: { app in
        app.get("test") { req async throws -> String in
          try await req.gameRoomAPI.isInLibrary(userID: "u1", volumeID: "v1", token: "tok")
            ? "present" : "absent"
        }
        try await app.testing().test(.GET, "test") { res in
          #expect(res.status == .ok)
          #expect(res.body.string == "absent")
        }
      })
  }

  @Test("isInLibrary throws on a non-ok response, for callers to fail open")
  func isInLibraryErrorThrows() async throws {
    try await withFakeGameRoomAPI(
      port: 18_794,
      configure: { fake in
        fake.get("users", ":userID", "library") { _ in
          Response(status: .internalServerError)
        }
      },
      body: { app in
        app.get("test") { req async throws -> String in
          do {
            _ = try await req.gameRoomAPI.isInLibrary(userID: "u1", volumeID: "v1", token: "tok")
            return "no-throw"
          } catch {
            return "threw"
          }
        }
        try await app.testing().test(.GET, "test") { res in
          #expect(res.status == .ok)
          #expect(res.body.string == "threw")
        }
      })
  }

  @Test("addLibraryEntry posts the volume id to the entries endpoint")
  func addLibraryEntryRequestShape() async throws {
    struct Body: Decodable {
      let volumeID: String
      enum CodingKeys: String, CodingKey {
        case volumeID = "volume_id"
      }
    }
    try await withFakeGameRoomAPI(
      port: 18_795,
      configure: { fake in
        fake.post("users", ":userID", "library", "entries") { req async throws -> Response in
          let body = try req.content.decode(Body.self)
          #expect(req.parameters.get("userID") == "u1")
          #expect(body.volumeID == "v1")
          #expect(req.headers.bearerAuthorization?.token == "tok")
          return Response(status: .ok)
        }
      },
      body: { app in
        app.get("test") { req async throws -> Response in
          try await req.gameRoomAPI.addLibraryEntry(userID: "u1", volumeID: "v1", token: "tok")
          return Response(status: .noContent)
        }
        try await app.testing().test(.GET, "test") { res in
          #expect(res.status == .noContent)
        }
      })
  }

  @Test("addLibraryEntry throws on a non-ok response")
  func addLibraryEntryErrorThrows() async throws {
    try await withFakeGameRoomAPI(
      port: 18_796,
      configure: { fake in
        fake.post("users", ":userID", "library", "entries") { _ in Response(status: .badRequest) }
      },
      body: { app in
        app.get("test") { req async throws -> String in
          do {
            try await req.gameRoomAPI.addLibraryEntry(userID: "u1", volumeID: "v1", token: "tok")
            return "no-throw"
          } catch {
            return "threw"
          }
        }
        try await app.testing().test(.GET, "test") { res in
          #expect(res.body.string == "threw")
        }
      })
  }

  @Test("removeLibraryEntry deletes the entry by volume id")
  func removeLibraryEntryRequestShape() async throws {
    try await withFakeGameRoomAPI(
      port: 18_797,
      configure: { fake in
        fake.delete("users", ":userID", "library", "entries", ":volumeID") { req -> Response in
          #expect(req.parameters.get("userID") == "u1")
          #expect(req.parameters.get("volumeID") == "v1")
          #expect(req.headers.bearerAuthorization?.token == "tok")
          return Response(status: .ok)
        }
      },
      body: { app in
        app.get("test") { req async throws -> Response in
          try await req.gameRoomAPI.removeLibraryEntry(userID: "u1", volumeID: "v1", token: "tok")
          return Response(status: .noContent)
        }
        try await app.testing().test(.GET, "test") { res in
          #expect(res.status == .noContent)
        }
      })
  }

  @Test("removeLibraryEntry throws on a non-ok response")
  func removeLibraryEntryErrorThrows() async throws {
    try await withFakeGameRoomAPI(
      port: 18_798,
      configure: { fake in
        fake.delete("users", ":userID", "library", "entries", ":volumeID") { _ in
          Response(status: .internalServerError)
        }
      },
      body: { app in
        app.get("test") { req async throws -> String in
          do {
            try await req.gameRoomAPI.removeLibraryEntry(userID: "u1", volumeID: "v1", token: "tok")
            return "no-throw"
          } catch {
            return "threw"
          }
        }
        try await app.testing().test(.GET, "test") { res in
          #expect(res.body.string == "threw")
        }
      })
  }
}
