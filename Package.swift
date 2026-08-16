// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "catalog-web",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        // 💧 A server-side Swift web framework.
        .package(url: "https://github.com/vapor/vapor.git", from: "4.99.0"),
        // 🍃 An expressive, performant, and extensible templating language.
        .package(url: "https://github.com/vapor/leaf.git", from: "4.3.0"),
        // 🔴 Redis-backed response caching, and a read-only connection to auth-web's shared
        // session store.
        .package(url: "https://github.com/vapor/redis.git", from: "4.10.0"),
        // 🔒 MD5 hashing for Gravatar URLs (avatar-menu) - already resolved transitively via
        // Vapor, declared explicitly here since SwiftPM requires a target's own dependencies to
        // be listed, not just present in the resolved graph.
        .package(url: "https://github.com/apple/swift-crypto.git", from: "4.5.1"),
        // 📊 Prometheus metrics.
        .package(url: "https://github.com/swift-server/swift-prometheus.git", from: "2.0.0"),
        // 🩻 Distributed tracing API + OTLP exporter, matching the Go services' OTLP/HTTP
        // export to the cluster's Jaeger collector (docs/service-conventions.md's Telemetry
        // section).
        .package(url: "https://github.com/apple/swift-distributed-tracing.git", from: "1.0.0"),
        .package(url: "https://github.com/swift-otel/swift-otel.git", from: "0.8.0"),
        // 🛠️ Shared admin-api client (banners, maintenance-mode) - replaces this app's own
        // hand-rolled AdminClient, see sweetrpg/platform#15.
        .package(url: "https://github.com/sweetrpg/admin-api-client.swift.git", from: "0.0.1"),
        // 📚 Shared catalog-api client (JSON:API fetch/decoding) - replaces this app's own
        // hand-rolled CatalogAPIClient, see sweetrpg/platform's api-client-sdks change.
        .package(
            url: "https://github.com/sweetrpg/catalog-api-client.swift.git",
            from: "0.0.9"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Leaf", package: "leaf"),
                .product(name: "Redis", package: "redis"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Prometheus", package: "swift-prometheus"),
                .product(name: "Tracing", package: "swift-distributed-tracing"),
                .product(name: "OTel", package: "swift-otel"),
                .product(name: "OTLPGRPC", package: "swift-otel"),
                .product(name: "AdminAPIClient", package: "admin-api-client.swift"),
                .product(name: "CatalogAPIClient", package: "catalog-api-client.swift"),
            ],
            // Resources/ and the top-level Public/ are shipped as plain directories next to the
            // built binary (see Dockerfile), not via SwiftPM resource bundling - Vapor's default
            // Leaf/Public-file resolution looks for them relative to the working directory, not
            // via Bundle.module.
            swiftSettings: [
                // Enable better optimizations when building in Release configuration. Despite
                // the use of the `.unsafeFlags` construct required by SwiftPM, this flag is
                // recommended for Release builds. See
                // <https://github.com/swift-server/guides/blob/main/docs/building.md#building-for-production>
                // for details.
                .unsafeFlags(["-cross-module-optimization"], .when(configuration: .release))
            ]
        ),
        .testTarget(
            name: "AppTests",
            dependencies: [
                .target(name: "App"),
                .product(name: "VaporTesting", package: "vapor"),
                .product(name: "Redis", package: "redis"),
            ]
        ),
    ]
)
