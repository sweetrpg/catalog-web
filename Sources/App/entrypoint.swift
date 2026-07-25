import Vapor

@main
enum Entrypoint {
  static func main() async throws {
    let env = try Environment.detect()
    let logLevel = Environment.get("LOG_LEVEL").flatMap(Logger.Level.init(rawValue:)) ?? .info
    LoggingSystem.bootstrapJSON(minimumLevel: logLevel)

    let app = try await Application.make(env)

    do {
      try await configure(app)
    } catch {
      app.logger.report(error: error)
      try? await app.asyncShutdown()
      throw error
    }
    try await app.execute()
    try await app.asyncShutdown()
  }
}
