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
        )
    ],
    targets: [
        .target(
            name: "EasyZipCore"
        ),
        .testTarget(
            name: "EasyZipCoreTests",
            dependencies: ["EasyZipCore"]
        )
    ]
)
