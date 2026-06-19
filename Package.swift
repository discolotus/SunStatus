// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SunStatus",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SunStatus", targets: ["SunStatus"]),
        .executable(name: "SunStatusIconRenderer", targets: ["SunStatusIconRenderer"]),
        .library(name: "SunStatusCore", targets: ["SunStatusCore"])
    ],
    targets: [
        .target(name: "SunStatusCore"),
        .target(
            name: "SunStatusUI",
            dependencies: ["SunStatusCore"]
        ),
        .executableTarget(
            name: "SunStatus",
            dependencies: [
                "SunStatusCore",
                "SunStatusUI"
            ]
        ),
        .executableTarget(name: "SunStatusIconRenderer"),
        .testTarget(
            name: "SunStatusCoreTests",
            dependencies: ["SunStatusCore"]
        )
    ]
)
