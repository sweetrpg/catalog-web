import Vapor

struct Auth0Config {
  let domain: String
  let clientID: String
  let clientSecret: String
  let callbackURL: String
  let audience: String?

  var isConfigured: Bool { !domain.isEmpty && !clientID.isEmpty }

  static func fromEnvironment() -> Auth0Config {
    Auth0Config(
      domain: Environment.get("AUTH0_DOMAIN") ?? "",
      clientID: Environment.get("AUTH0_CLIENT_ID") ?? "",
      clientSecret: Environment.get("AUTH0_CLIENT_SECRET") ?? "",
      callbackURL: Environment.get("AUTH0_CALLBACK_URL") ?? "http://localhost:8080/auth/callback",
      audience: Environment.get("AUTH0_AUDIENCE")
    )
  }

  func authorizeURL(state: String) -> String {
    var components = URLComponents(string: "https://\(domain)/authorize")!
    var items = [
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "client_id", value: clientID),
      URLQueryItem(name: "redirect_uri", value: callbackURL),
      URLQueryItem(name: "scope", value: "openid profile email"),
      URLQueryItem(name: "state", value: state),
    ]
    if let audience { items.append(URLQueryItem(name: "audience", value: audience)) }
    components.queryItems = items
    return components.url!.absoluteString
  }

  var logoutURL: String {
    var components = URLComponents(string: "https://\(domain)/v2/logout")!
    components.queryItems = [
      URLQueryItem(name: "client_id", value: clientID),
      URLQueryItem(
        name: "returnTo",
        value: callbackURL.replacingOccurrences(
          of: "/auth/callback", with: "/")),
    ]
    return components.url!.absoluteString
  }
}

extension Application {
  private struct Auth0ConfigKey: StorageKey {
    typealias Value = Auth0Config
  }

  var auth0Config: Auth0Config {
    get {
      guard let config = storage[Auth0ConfigKey.self] else {
        let config = Auth0Config.fromEnvironment()
        storage[Auth0ConfigKey.self] = config
        return config
      }
      return config
    }
    set { storage[Auth0ConfigKey.self] = newValue }
  }
}
