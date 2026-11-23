import Vapor

extension Request {
  private struct ProfileResponse: Decodable {
    let userId: String?
    enum CodingKeys: String, CodingKey { case userId = "user_id" }
  }

  /// The canonical `users._id` that game-room-api keys libraries by, resolved from users-api's
  /// `GET /profile` with the caller's own bearer token (no service token), same as
  /// game-room-web. Falls back to the Auth0 subject when the profile is unresolvable. Resolved
  /// per request because the shared session is read-only here.
  func canonicalUserID(for user: SessionUser) async -> String {
    let uri = URI(string: backendConfig.usersAPIURL + "/profile")
    do {
      let response = try await client.get(uri) { clientReq in
        clientReq.headers.bearerAuthorization = BearerAuthorization(token: user.accessToken)
        clientReq.timeout = .seconds(5)
      }
      guard response.status == .ok,
        let id = try response.content.decode(ProfileResponse.self).userId, !id.isEmpty
      else { return user.sub }
      return id
    } catch {
      logger.warning("canonicalUserID: users-api profile lookup failed: \(error)")
      return user.sub
    }
  }
}
