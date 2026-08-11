import Vapor

/// The identity `auth-web` writes into the shared session store - mirrors its own `SessionUser`
/// model. `roles` comes from `users-api`'s verified `/authz/check` response, not an unverified
/// local ID-token decode - this app no longer decodes any token itself (that unverified decode,
/// `decodeUnverifiedJWTPayload`, was removed along with `AuthController`/`Auth0Config`; see
/// design.md's "auth-web is the sole owner of the Authorization Code exchange" decision in
/// platform's add-user-api-authn-authz change).
struct SessionUser: Codable {
  let sub: String
  let name: String
  let email: String?
  let roles: [String]
  /// The Auth0 access token `auth-web` exchanged at login - forwarded as the Bearer token on
  /// authenticated writes to catalog-api (`PATCH /volumes/:id` and the proposed-change review
  /// endpoints). See platform's volume-edit-with-approval-workflow change.
  let accessToken: String
}
