// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CineLarkKit",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(name: "CineLarkDomain", targets: ["CineLarkDomain"]),
        .library(name: "CineLarkUHDNow", targets: ["CineLarkUHDNow"]),
        .library(name: "CineLarkPersistence", targets: ["CineLarkPersistence"]),
        .library(name: "CineLarkPlayback", targets: ["CineLarkPlayback"]),
        .library(name: "CineLarkRemote", targets: ["CineLarkRemote"])
    ],
    targets: [
        .target(name: "CineLarkDomain"),
        .target(
            name: "CineLarkUHDNow",
            dependencies: ["CineLarkDomain"]
        ),
        .target(
            name: "CineLarkPersistence",
            dependencies: ["CineLarkDomain"]
        ),
        .target(
            name: "CineLarkPlayback",
            dependencies: ["CineLarkDomain"]
        ),
        .target(name: "CineLarkRemote"),
        .testTarget(
            name: "CineLarkUHDNowTests",
            dependencies: ["CineLarkDomain", "CineLarkUHDNow"]
        ),
        .testTarget(
            name: "CineLarkPersistenceTests",
            dependencies: ["CineLarkDomain", "CineLarkPersistence"]
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
