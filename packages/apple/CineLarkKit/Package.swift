// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CineLarkKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "CineLarkDomain", targets: ["CineLarkDomain"]),
        .library(name: "CineLarkUHDNow", targets: ["CineLarkUHDNow"]),
        .library(name: "CineLarkPersistence", targets: ["CineLarkPersistence"]),
        .library(name: "CineLarkPlayback", targets: ["CineLarkPlayback"])
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
        .testTarget(
            name: "CineLarkUHDNowTests",
            dependencies: ["CineLarkDomain", "CineLarkUHDNow"]
        )
    ]
)
