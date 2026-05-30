// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "EasyZip",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "EasyZipCore",
            targets: ["EasyZipCore"]
        ),
        .executable(
            name: "EasyZipApp",
            targets: ["EasyZipApp"]
        )
    ],
    targets: [
        .target(
            name: "EasyZipCore",
            linkerSettings: [
                .linkedLibrary("archive")
            ]
        ),
        .testTarget(
            name: "EasyZipCoreTests",
            dependencies: ["EasyZipCore"]
        ),
        .executableTarget(
            name: "EasyZipApp",
            dependencies: ["EasyZipCore"]
        )
    ]
)
