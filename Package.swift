// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SunStatus",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SunStatus", targets: ["SunStatus"]),
        .library(name: "SunStatusCore", targets: ["SunStatusCore"])
    ],
    targets: [
        .target(name: "SunStatusCore"),
        .executableTarget(
            name: "SunStatus",
            dependencies: ["SunStatusCore"]
        ),
        .testTarget(
            name: "SunStatusCoreTests",
            dependencies: ["SunStatusCore"]
        )
    ]
)
