// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "OpenIsland",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "OpenIslandCore",
            targets: ["OpenIslandCore"]
        ),
        .executable(
            name: "OpenIslandHooks",
            targets: ["OpenIslandHooks"]
        ),
        .executable(
            name: "OpenIslandSetup",
            targets: ["OpenIslandSetup"]
        ),
        .executable(name: "MiniMaxCodeSourceProbe", targets: ["MiniMaxCodeSourceProbe"]),
        .executable(
            name: "OpenIslandApp",
            targets: ["OpenIslandApp"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
    ],
    targets: [
        .target(
            name: "OpenIslandCore"
        ),
        .executableTarget(
            name: "OpenIslandHooks",
            dependencies: ["OpenIslandCore"]
        ),
        .executableTarget(
            name: "OpenIslandSetup",
            dependencies: ["OpenIslandCore"]
        ),
        .executableTarget(
            name: "MiniMaxCodeSourceProbe",
            path: "Integrations/MiniMaxCode/scripts",
            exclude: ["core.mjs", "hook.mjs", "install.mjs", "source.mjs"],
            sources: ["source-probe.swift"]
        ),
        .executableTarget(
            name: "OpenIslandApp",
            dependencies: [
                "OpenIslandCore",
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [
                .process("Resources"),
                .copy("AgentIntegrationPackages"),
            ]
        ),
        .testTarget(
            name: "OpenIslandCoreTests",
            dependencies: ["OpenIslandCore"]
        ),
        .testTarget(
            name: "OpenIslandAppTests",
            dependencies: ["OpenIslandApp", "OpenIslandCore"]
        ),
    ]
)
