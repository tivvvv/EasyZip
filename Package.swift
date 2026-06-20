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
            name: "EasyZipShared"
        ),
        .target(
            name: "EasyZipCore",
            linkerSettings: [
                .linkedLibrary("archive")
            ]
        ),
        .target(
            name: "EasyZipTestSupport",
            path: "Tests/EasyZipTestSupport"
        ),
        .testTarget(
            name: "EasyZipCoreTests",
            dependencies: ["EasyZipCore", "EasyZipTestSupport"]
        ),
        .testTarget(
            name: "EasyZipSharedTests",
            dependencies: ["EasyZipShared", "EasyZipTestSupport"]
        ),
        .testTarget(
            name: "EasyZipAppTests",
            dependencies: ["EasyZipApp"]
        ),
        .executableTarget(
            name: "EasyZipApp",
            dependencies: ["EasyZipCore", "EasyZipShared"]
        )
    ]
)
