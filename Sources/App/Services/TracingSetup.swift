import OTLPGRPC
import OTel
import ServiceLifecycle
import Tracing
import Vapor

/// Bootstraps distributed tracing, exported via OTLP/gRPC to the cluster's collector - the same
/// destination the Go services export to via OTLP/HTTP (docs/service-conventions.md's Telemetry
/// section; `OTEL_EXPORTER_OTLP_ENDPOINT`), but over gRPC since that's the only OTLP transport
/// `swift-otel` ships in the version pinned here (no `OTLPHTTP` product exists yet). If the
/// collector's gRPC receiver (typically :4317) isn't enabled, traces from this app won't arrive
/// even though the endpoint variable is shared with the Go services' HTTP receiver (:4318).
enum TracingSetup {
  static func bootstrap(_ app: Application) async throws {
    let environment = OTelEnvironment.detected()
    let resourceDetection = OTelResourceDetection(detectors: [
      OTelProcessResourceDetector(),
      OTelEnvironmentResourceDetector(environment: environment),
      .manual(OTelResource(attributes: ["service.name": "catalog-web"])),
    ])
    let resource = await resourceDetection.resource(environment: environment, logLevel: .info)

    let exporter = try OTLPGRPCSpanExporter(configuration: .init(environment: environment))
    let processor = OTelBatchSpanProcessor(
      exporter: exporter, configuration: .init(environment: environment))
    let tracer = OTelTracer(
      idGenerator: OTelRandomIDGenerator(),
      sampler: OTelConstantSampler(isOn: true),
      propagator: OTelW3CPropagator(),
      processor: processor,
      environment: environment,
      resource: resource
    )
    InstrumentationSystem.bootstrap(tracer)

    app.lifecycle.use(OTelLifecycleHandler(tracer: tracer))
  }
}

/// Runs the tracer's background batch-export loop for the app's lifetime. `OTelTracer.run()`
/// (its `Service` conformance) only returns when cancelled, so it's launched as an unstructured
/// task here rather than awaited directly - Vapor's `LifecycleHandler` doesn't have a slot for a
/// long-running task the way swift-service-lifecycle's `ServiceGroup` does.
private final class OTelLifecycleHandler: LifecycleHandler, @unchecked Sendable {
  let tracer: any Service
  var task: Task<Void, Error>?

  init(tracer: any Service) {
    self.tracer = tracer
  }

  func didBoot(_ application: Application) throws {
    let tracer = self.tracer
    task = Task { try await tracer.run() }
  }

  func shutdown(_ application: Application) {
    task?.cancel()
  }
}
