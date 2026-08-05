// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Runestone",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(name: "Runestone", targets: ["Runestone"]),
        .library(name: "EditorIntelligence", targets: ["EditorIntelligence"]),
        .library(name: "RunestoneGraphQLLanguage", targets: ["RunestoneGraphQLLanguage"])
    ],
    dependencies: [
        .package(url: "https://github.com/tree-sitter/tree-sitter", .upToNextMinor(from: "0.20.9"))
    ],
    targets: [
        .target(name: "EditorIntelligence", dependencies: []),
        .target(name: "Runestone", dependencies: [
            "EditorIntelligence",
            .product(name: "TreeSitter", package: "tree-sitter")
        ], exclude: [
            "Documentation.docc"
        ], resources: [
            .copy("PrivacyInfo.xcprivacy"),
            .process("TextView/Appearance/Theme.xcassets")
        ]),
        .executableTarget(name: "SmokeTest", dependencies: ["Runestone"]),
        .target(name: "TestTreeSitterLanguages", cSettings: [
            .unsafeFlags(["-w"])
        ]),
        .target(name: "TreeSitterGraphQL", cSettings: [
            .headerSearchPath("src"),
            .unsafeFlags(["-w"])
        ]),
        .target(
            name: "RunestoneGraphQLLanguage",
            dependencies: [
                "Runestone",
                "TreeSitterGraphQL"
            ],
            resources: [
                .copy("highlights.scm")
            ]
        ),
        .testTarget(name: "RunestoneTests", dependencies: [
            "Runestone",
            "EditorIntelligence",
            "TestTreeSitterLanguages",
            "RunestoneGraphQLLanguage"
        ])
    ]
)
