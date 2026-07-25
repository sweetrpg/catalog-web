import Foundation
import Vapor

/// Minimal user identity carried in the session cookie after login. Decoded from the Auth0 ID
/// token's claims - see the SECURITY note on `decodeUnverifiedJWTPayload` before trusting this
/// for anything beyond display.
///
/// Stored directly as JSON in the session (via `Request.currentUser`), not through Vapor's
/// `SessionAuthenticator` protocol - that machinery is built around looking up a full user
/// record from a stored ID (e.g. a database row keyed by session ID), which doesn't fit here:
/// there's no local user record to look up, the whole identity already came from Auth0.
struct SessionUser: Codable {
  let sub: String
  let name: String
  let email: String?
}

/// SECURITY: this decodes the JWT payload without verifying its signature. It is only safe to
/// use for display (showing a name in the header) because the token arrives directly from
/// Auth0's token endpoint over a server-to-server TLS connection in `AuthController.callback` -
/// it is never accepted from anywhere else (e.g. a client-supplied header or cookie), so there
/// is no forgery path today. If this token, or any bearer token derived from it, is ever used to
/// authorize an action (not just to render a name), add real signature verification against
/// Auth0's JWKS endpoint first - do not extend this decoder's role without doing that.
func decodeUnverifiedJWTPayload(_ jwt: String) -> [String: Any]? {
  let parts = jwt.split(separator: ".")
  guard parts.count == 3 else { return nil }
  var base64 = String(parts[1])
    .replacingOccurrences(of: "-", with: "+")
    .replacingOccurrences(of: "_", with: "/")
  while base64.count % 4 != 0 { base64 += "=" }
  guard let data = Data(base64Encoded: base64),
    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  else { return nil }
  return json
}
