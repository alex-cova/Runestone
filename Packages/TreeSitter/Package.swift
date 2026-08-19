// swift-tools-version: 5.8

import PackageDescription

// Vendored from tree-sitter v0.26.12 with an amalgamation build so Swift can
// import the C API on current Xcode toolchains (see tree-sitter/tree-sitter#5523).
let package = Package(
    name: "TreeSitter",
    products: [
        .library(name: "TreeSitter", targets: ["TreeSitter"])
    ],
    targets: [
        .target(
            name: "TreeSitter",
            path: "lib",
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
        )
    ],
    cLanguageStandard: .c11
)
