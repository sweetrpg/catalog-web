import Vapor

/// Handles the Auth0 Authorization Code flow: redirect to Auth0's Universal Login, exchange the
/// returned code for tokens, and stash a minimal user identity in the session.
///
/// This is the "frontend component to serve the login page" - Auth0's own hosted Universal
/// Login page does the actual credential collection, so `/auth/login` only needs to redirect
/// there. `login.leaf` exists as a pre-redirect landing page (useful for a "Log in" link target
/// with its own URL, and a fallback if Auth0 isn't configured yet in this environment).
struct AuthController: RouteCollection {
  func boot(routes: RoutesBuilder) throws {
    routes.get("login", use: loginPage)
    routes.get("auth", "login", use: redirectToAuth0)
    routes.get("auth", "callback", use: callback)
    routes.post("auth", "logout", use: logout)
  }

  @Sendable
  func loginPage(req: Request) async throws -> View {
    try await req.view.render(
      "auth/login",
      LoginContext(
        auth0Configured: req.application.auth0Config.isConfigured,
        meta: PageMeta(req)
      ))
  }

  @Sendable
  func redirectToAuth0(req: Request) async throws -> Response {
    let config = req.application.auth0Config
    guard config.isConfigured else {
      req.logger.warning("AUTH0_DOMAIN/AUTH0_CLIENT_ID not set - cannot start login flow")
      return req.redirectLocal(to: "/login")
    }
    let state = [UInt8].random(count: 16).base64String()
    req.session.data["auth_state"] = state
    return req.redirect(to: config.authorizeURL(state: state))
  }

  @Sendable
  func callback(req: Request) async throws -> Response {
    struct CallbackQuery: Content {
      let code: String?
      let state: String?
      let error: String?
    }
    let query = try req.query.decode(CallbackQuery.self)

    if let error = query.error {
      req.logger.warning("Auth0 callback returned an error: \(error)")
      return req.redirectLocal(to: "/login")
    }
    guard let code = query.code, query.state == req.session.data["auth_state"] else {
      req.logger.warning("Auth0 callback missing code or state mismatch")
      return req.redirectLocal(to: "/login")
    }
    req.session.data["auth_state"] = nil

    let config = req.application.auth0Config
    struct TokenResponse: Content {
      let idToken: String

      enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
      }
    }
    let tokenResponse = try await req.client.post(
      URI(string: "https://\(config.domain)/oauth/token"),
      content: [
        "grant_type": "authorization_code",
        "client_id": config.clientID,
        "client_secret": config.clientSecret,
        "code": code,
        "redirect_uri": config.callbackURL,
      ] as [String: String]
    ).content.decode(TokenResponse.self)

    guard let claims = decodeUnverifiedJWTPayload(tokenResponse.idToken),
      let sub = claims["sub"] as? String
    else {
      req.logger.error("Could not decode Auth0 ID token claims")
      return req.redirectLocal(to: "/login")
    }
    req.currentUser = SessionUser(
      sub: sub,
      name: (claims["name"] as? String) ?? (claims["email"] as? String) ?? "Reader",
      email: claims["email"] as? String
    )
    return req.redirectLocal(to: "/")
  }

  @Sendable
  func logout(req: Request) async throws -> Response {
    req.currentUser = nil
    req.session.destroy()
    let config = req.application.auth0Config
    return config.isConfigured ? req.redirect(to: config.logoutURL) : req.redirectLocal(to: "/")
  }
}

struct LoginContext: Content {
  let auth0Configured: Bool
  let meta: PageMeta
}
