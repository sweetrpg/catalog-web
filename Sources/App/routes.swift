import Vapor

func routes(_ app: Application) throws {
  // Shallow liveness only - see the TODO in configure.swift about a future deep check.
  app.get("status", "ping") { req -> [String: String] in
    [
      "status": "ok", "hostname": Environment.get("HOSTNAME") ?? "unknown",
      "version": req.buildInfo.version,
    ]
  }

  try app.register(collection: CatalogController())
  try app.register(collection: VolumesController())
  try app.register(collection: PublishersController())
  try app.register(collection: StudiosController())
  try app.register(collection: PersonsController())
  try app.register(collection: LicensesController())
  try app.register(collection: ShelvesController())
}
