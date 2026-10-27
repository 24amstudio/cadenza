// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CadenzaHost",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "CadenzaHost", targets: ["CadenzaHost"]),
        .executable(name: "CadenzaUpdater", targets: ["CadenzaUpdater"]),
        .executable(name: "CadenzaRelease", targets: ["CadenzaRelease"]),
    ],
    targets: [
        .systemLibrary(name: "CSQLite", path: "Sources/CSQLite"),
        .target(name: "CadenzaSecurity", path: "Sources/CadenzaSecurity"),
        .executableTarget(
            name: "CadenzaHost",
            dependencies: ["CSQLite", "CadenzaSecurity"],
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
            name: "CadenzaRelease", dependencies: ["CadenzaSecurity"],
            path: "Sources/CadenzaRelease"
        ),
        .testTarget(
            name: "CadenzaHostTests",
            dependencies: ["CadenzaHost", "CadenzaSecurity"], path: "Tests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
