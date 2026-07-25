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
        // 🔴 Redis-backed session/response caching.
        .package(url: "https://github.com/vapor/redis.git", from: "4.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Leaf", package: "leaf"),
                .product(name: "Redis", package: "redis"),
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
            ]
        ),
    ]
)
