import Metrics
import Prometheus
import Vapor

/// Bootstraps swift-metrics with a Prometheus backend and exposes it at `/metrics`, matching
/// the Go services' `gin-metrics` convention (docs/service-conventions.md's Telemetry section) -
/// same path, same text exposition format, scraped the same way via a `PodMonitor`.
enum MetricsSetup {
  static func bootstrap(_ app: Application) {
    let factory = PrometheusMetricsFactory()
    MetricsSystem.bootstrap(factory)

    app.get("metrics") { req -> Response in
      let text = factory.registry.emitToString()
      return Response(
        status: .ok,
        headers: ["content-type": "text/plain; version=0.0.4"],
        body: .init(string: text)
      )
    }
  }
}
