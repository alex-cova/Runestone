// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "MacExample",
    platforms: [
        .macOS(.v12)
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "MacExample",
            dependencies: [
                .product(name: "Runestone", package: "Runestone")
            ]
        )
    ]
)
