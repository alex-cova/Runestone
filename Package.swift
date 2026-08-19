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
            "TreeSitter",
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
