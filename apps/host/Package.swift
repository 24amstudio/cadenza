// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CadenzaHost",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "CadenzaHost", targets: ["CadenzaHost"]),
        .executable(name: "CadenzaWatchdog", targets: ["CadenzaWatchdog"]),
        .executable(name: "CadenzaUpdater", targets: ["CadenzaUpdater"]),
        .executable(name: "CadenzaRelease", targets: ["CadenzaRelease"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/ml-explore/mlx-swift.git",
            exact: "0.33.0"
        ),
        .package(
            url: "https://github.com/xocialize/mel-roformer-mlx-swift.git",
            revision: "22162f8fd5cd8cc09abc47a87c1ecddf3baf5ee3"
        ),
        .package(
            url: "https://github.com/huggingface/swift-transformers.git",
            revision: "573e5c9036c2f136b3a8a071da8e8907322403d0"
        ),
    ],
    targets: [
        .systemLibrary(name: "CSQLite", path: "Sources/CSQLite"),
        .target(name: "CadenzaSecurity", path: "Sources/CadenzaSecurity"),
        .executableTarget(
            name: "CadenzaHost",
            dependencies: [
                "CSQLite", "CadenzaSecurity",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "SwiftRoFormer", package: "mel-roformer-mlx-swift"),
                .product(name: "Hub", package: "swift-transformers"),
            ],
            path: ".",
            exclude: [
                "Sources/CSQLite", "Sources/CadenzaSecurity", "Sources/CadenzaUpdater",
                "Sources/CadenzaRelease", "Tests", "tools", "Scripts", "README.md",
            ],
            sources: ["Sources/CadenzaHost"],
            resources: [.copy("storage"), .copy("Resources")]
        ),
        .executableTarget(
            name: "CadenzaUpdater", dependencies: ["CadenzaSecurity"],
            path: "Sources/CadenzaUpdater"
        ),
        .executableTarget(
            name: "CadenzaWatchdog", dependencies: ["CSQLite"],
            path: "Sources/CadenzaWatchdog"
        ),
        .executableTarget(
            name: "CadenzaRelease", dependencies: ["CadenzaSecurity"],
            path: "Sources/CadenzaRelease"
        ),
        .executableTarget(
            name: "CadenzaSingBenchmark",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "SwiftRoFormer", package: "mel-roformer-mlx-swift"),
            ],
            path: "tools/sing",
            sources: ["Benchmark.swift"]
        ),
        .testTarget(
            name: "CadenzaHostTests",
            dependencies: ["CadenzaHost", "CadenzaSecurity"], path: "Tests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
