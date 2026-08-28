// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CineLarkKit",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(name: "CineLarkDomain", targets: ["CineLarkDomain"]),
        .library(name: "CineLarkPluginAPI", targets: ["CineLarkPluginAPI"]),
        .library(name: "CineLarkCatalog", targets: ["CineLarkCatalog"]),
        .library(name: "CineLarkProfile", targets: ["CineLarkProfile"]),
        .library(name: "CineLarkInsights", targets: ["CineLarkInsights"]),
        .library(name: "CineLarkEmby", targets: ["CineLarkEmby"]),
        .library(name: "CineLarkPersistence", targets: ["CineLarkPersistence"]),
        .library(name: "CineLarkPlayback", targets: ["CineLarkPlayback"]),
        .library(name: "CineLarkRemote", targets: ["CineLarkRemote"]),
        .library(name: "CineLarkGateway", targets: ["CineLarkGateway"])
    ],
    targets: [
        .target(name: "CineLarkDomain"),
        .target(
            name: "CineLarkPluginAPI",
            dependencies: ["CineLarkDomain"]
        ),
        .target(
            name: "CineLarkCatalog",
            dependencies: ["CineLarkDomain", "CineLarkPluginAPI"]
        ),
        .target(
            name: "CineLarkProfile",
            dependencies: ["CineLarkDomain", "CineLarkPluginAPI"]
        ),
        .target(
            name: "CineLarkInsights",
            dependencies: [
                "CineLarkDomain", "CineLarkPluginAPI", "CineLarkCatalog",
                "CineLarkProfile"
            ]
        ),
        .target(
            name: "CineLarkEmby",
            dependencies: ["CineLarkDomain", "CineLarkPluginAPI"]
        ),
        .target(name: "CineLarkPersistence"),
        .target(
            name: "CineLarkPlayback",
            dependencies: ["CineLarkDomain"]
        ),
        .target(name: "CineLarkRemote"),
        .target(
            name: "CineLarkGateway",
            dependencies: ["CineLarkPlayback", "CineLarkRemote"]
        ),
        .testTarget(
            name: "CineLarkPluginAPITests",
            dependencies: ["CineLarkDomain", "CineLarkPluginAPI"]
        ),
        .testTarget(
            name: "CineLarkCatalogTests",
            dependencies: ["CineLarkDomain", "CineLarkPluginAPI", "CineLarkCatalog"]
        ),
        .testTarget(
            name: "CineLarkProfileTests",
            dependencies: ["CineLarkDomain", "CineLarkPluginAPI", "CineLarkProfile"]
        ),
        .testTarget(
            name: "CineLarkInsightsTests",
            dependencies: [
                "CineLarkDomain", "CineLarkPluginAPI", "CineLarkCatalog",
                "CineLarkProfile", "CineLarkInsights"
            ]
        ),
        .testTarget(
            name: "CineLarkEmbyTests",
            dependencies: ["CineLarkDomain", "CineLarkPluginAPI", "CineLarkEmby"],
            resources: [.process("Fixtures")]
        ),
        .testTarget(
            name: "CineLarkPersistenceTests",
            dependencies: ["CineLarkPersistence"]
        ),
        .testTarget(
            name: "CineLarkPlaybackTests",
            dependencies: ["CineLarkDomain", "CineLarkPlayback"]
        ),
        .testTarget(
            name: "CineLarkRemoteTests",
            dependencies: ["CineLarkRemote"]
        )
    ]
)
