import Vapor

func routes(_ app: Application) throws {
  // Shallow liveness only - see the TODO in configure.swift about a future deep check.
  app.get("status", "ping") { req -> [String: String] in
    ["status": "ok", "hostname": Environment.get("HOSTNAME") ?? "unknown"]
  }

  try app.register(collection: CatalogController())
  try app.register(collection: ShelvesController())
  try app.register(collection: AuthController())
}
