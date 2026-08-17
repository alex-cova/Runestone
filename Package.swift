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
        .library(name: "EditorIntelligenceLSP", targets: ["EditorIntelligenceLSP"]),
        .library(name: "RunestoneGraphQLLanguage", targets: ["RunestoneGraphQLLanguage"])
    ],
    dependencies: [
        .package(url: "https://github.com/tree-sitter/tree-sitter", .upToNextMinor(from: "0.20.9")),
        .package(url: "https://github.com/ChimeHQ/LanguageClient", from: "0.8.0"),
        .package(url: "https://github.com/ChimeHQ/LanguageServerProtocol", from: "0.14.0"),
        .package(url: "https://github.com/ChimeHQ/TextFormation", from: "0.9.0")
    ],
    targets: [
        .target(name: "EditorIntelligence", dependencies: []),
        .target(
            name: "EditorIntelligenceLSP",
            dependencies: [
                "EditorIntelligence",
                .product(name: "LanguageClient", package: "LanguageClient"),
                .product(name: "LanguageServerProtocol", package: "LanguageServerProtocol")
            ]
        ),
        .target(name: "Runestone", dependencies: [
            "EditorIntelligence",
            .product(name: "TreeSitter", package: "tree-sitter"),
            .product(name: "TextFormation", package: "TextFormation")
        ], exclude: [
            "Documentation.docc"
        ], resources: [
            .copy("PrivacyInfo.xcprivacy"),
            .process("TextView/Appearance/Theme.xcassets")
        ]),
        .executableTarget(name: "SmokeTest", dependencies: ["Runestone"]),
        .executableTarget(
            name: "MacExample",
            dependencies: ["Runestone", "TestTreeSitterLanguages"],
            path: "Example/MacExample"
        ),
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
            "EditorIntelligenceLSP",
            "TestTreeSitterLanguages",
            "RunestoneGraphQLLanguage"
        ])
    ]
)
