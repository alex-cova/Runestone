// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
// Swift 6 language mode is enabled on library, test, harness, and example targets.
// Do not set `defaultIsolation: MainActor` (SE-0476): EIP actors, background parse,
// and off-main search must stay nonisolated by default.

import PackageDescription

let swift6: [SwiftSetting] = [.swiftLanguageMode(.v6)]

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
        .library(name: "RunestoneGraphQLLanguage", targets: ["RunestoneGraphQLLanguage"]),
        .library(name: "RunestoneMarkdownLanguage", targets: ["RunestoneMarkdownLanguage"])
    ],
    dependencies: [
        .package(url: "https://github.com/ChimeHQ/LanguageClient", from: "0.8.0"),
        .package(url: "https://github.com/ChimeHQ/LanguageServerProtocol", from: "0.14.0"),
        .package(url: "https://github.com/ChimeHQ/TextFormation", from: "0.9.0")
    ],
    targets: [
        .target(
            name: "TreeSitter",
            path: "Packages/TreeSitter/lib",
            exclude: [
                "src/unicode/ICU_SHA",
                "src/unicode/README.md",
                "src/unicode/LICENSE",
                "src/wasm/stdlib-symbols.txt"
            ],
            sources: ["src/lib.c"],
            cSettings: [
                .headerSearchPath("src"),
                .define("_POSIX_C_SOURCE", to: "200112L"),
                .define("_DEFAULT_SOURCE"),
                .define("_BSD_SOURCE"),
                .define("_DARWIN_C_SOURCE")
            ]
        ),
        .target(name: "EditorIntelligence", dependencies: [], swiftSettings: swift6),
        .target(
            name: "EditorIntelligenceLSP",
            dependencies: [
                "EditorIntelligence",
                .product(name: "LanguageClient", package: "LanguageClient"),
                .product(name: "LanguageServerProtocol", package: "LanguageServerProtocol")
            ],
            swiftSettings: swift6
        ),
        .target(name: "Runestone", dependencies: [
            "EditorIntelligence",
            "TreeSitter",
            .product(name: "TextFormation", package: "TextFormation")
        ], exclude: [
            "Documentation.docc"
        ], resources: [
            .copy("PrivacyInfo.xcprivacy"),
            .process("TextView/Appearance/Theme.xcassets")
        ], swiftSettings: swift6),
        .executableTarget(name: "SmokeTest", dependencies: ["Runestone"], swiftSettings: swift6),
        .executableTarget(
            name: "PerfHarness",
            dependencies: ["Runestone", "RunestoneMarkdownLanguage"],
            path: "Tools/PerfHarness/Sources",
            swiftSettings: swift6
        ),
        .executableTarget(
            name: "MacExample",
            dependencies: ["Runestone", "TestTreeSitterLanguages"],
            path: "Example/MacExample",
            swiftSettings: swift6
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
            ],
            swiftSettings: swift6
        ),
        .target(name: "TreeSitterMarkdown", exclude: ["LICENSE", "VERSION"], cSettings: [
            .headerSearchPath("src"),
            .unsafeFlags(["-w"])
        ]),
        .target(name: "TreeSitterMarkdownInline", exclude: ["LICENSE", "VERSION"], cSettings: [
            .headerSearchPath("src"),
            .unsafeFlags(["-w"])
        ]),
        .target(
            name: "RunestoneMarkdownLanguage",
            dependencies: [
                "Runestone",
                "TreeSitterMarkdown",
                "TreeSitterMarkdownInline"
            ],
            resources: [
                .copy("Queries")
            ],
            swiftSettings: swift6
        ),
        .testTarget(name: "RunestoneTests", dependencies: [
            "Runestone",
            "EditorIntelligence",
            "EditorIntelligenceLSP",
            "TestTreeSitterLanguages",
            "RunestoneGraphQLLanguage",
            "RunestoneMarkdownLanguage"
        ], swiftSettings: swift6)
    ]
)
