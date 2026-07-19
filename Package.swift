// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "swift-skeleton",
    platforms: [.macOS(.v13)],
    products: [
        .library(
            name: "SkeletonIndexCore",
            targets: ["SkeletonIndexCore"]
        ),
        .library(
            name: "SkeletonSwiftParser",
            targets: ["SkeletonSwiftParser"]
        ),
        .library(
            name: "SkeletonKotlinParser",
            targets: ["SkeletonKotlinParser"]
        ),
        .library(
            name: "SkeletonTypeScriptParser",
            targets: ["SkeletonTypeScriptParser"]
        ),
        .library(
            name: "SkeletonGoParser",
            targets: ["SkeletonGoParser"]
        ),
        .library(
            name: "SkeletonZigParser",
            targets: ["SkeletonZigParser"]
        ),
        .library(
            name: "SkeletonRustParser",
            targets: ["SkeletonRustParser"]
        ),
        .library(
            name: "SkeletonCppParser",
            targets: ["SkeletonCppParser"]
        ),
        .library(
            name: "SkeletonPythonParser",
            targets: ["SkeletonPythonParser"]
        ),
        .library(
            name: "SkeletonJavaParser",
            targets: ["SkeletonJavaParser"]
        ),
        .library(
            name: "SkeletonIndexClient",
            targets: ["SkeletonIndexClient"]
        ),
        .executable(
            name: "skltn",
            targets: ["skltn"]
        ),
    ],
    traits: [
        .default(enabledTraits: ["kotlin", "typescript", "go", "zig", "rust", "cpp", "python", "java"]),
        "kotlin",
        "typescript",
        "go",
        "zig",
        "rust",
        "cpp",
        "python",
        "java",
    ],
    dependencies: [
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter.git", from: "0.9.0"),
    ],
    targets: [
        // MARK: - Core
        .target(
            name: "SkeletonIndexCore"
        ),

        // MARK: - Grammar C targets
        .target(
            name: "TreeSitterSwiftGrammar",
            path: "Sources/TreeSitterSwiftGrammar",
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath(".")]
        ),
        .target(
            name: "TreeSitterKotlinGrammar",
            path: "Sources/TreeSitterKotlinGrammar",
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath(".")]
        ),
        .target(
            name: "TreeSitterTypeScriptGrammar",
            path: "Sources/TreeSitterTypeScriptGrammar",
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath(".")]
        ),
        .target(
            name: "TreeSitterGoGrammar",
            path: "Sources/TreeSitterGoGrammar",
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath(".")]
        ),
        .target(
            name: "TreeSitterZigGrammar",
            path: "Sources/TreeSitterZigGrammar",
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath(".")]
        ),
        .target(
            name: "TreeSitterRustGrammar",
            path: "Sources/TreeSitterRustGrammar",
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath(".")]
        ),
        .target(
            name: "TreeSitterCppGrammar",
            path: "Sources/TreeSitterCppGrammar",
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath(".")]
        ),
        .target(
            name: "TreeSitterPythonGrammar",
            path: "Sources/TreeSitterPythonGrammar",
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath(".")]
        ),
        .target(
            name: "TreeSitterJavaGrammar",
            path: "Sources/TreeSitterJavaGrammar",
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath(".")]
        ),

        // MARK: - Parser Swift targets
        .target(
            name: "SkeletonSwiftParser",
            dependencies: [
                "SkeletonIndexCore",
                "TreeSitterSwiftGrammar",
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
            ]
        ),
        .target(
            name: "SkeletonKotlinParser",
            dependencies: [
                "SkeletonIndexCore",
                "TreeSitterKotlinGrammar",
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
            ]
        ),
        .target(
            name: "SkeletonTypeScriptParser",
            dependencies: [
                "SkeletonIndexCore",
                "TreeSitterTypeScriptGrammar",
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
            ]
        ),
        .target(
            name: "SkeletonGoParser",
            dependencies: [
                "SkeletonIndexCore",
                "TreeSitterGoGrammar",
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
            ]
        ),
        .target(
            name: "SkeletonZigParser",
            dependencies: [
                "SkeletonIndexCore",
                "TreeSitterZigGrammar",
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
            ]
        ),
        .target(
            name: "SkeletonRustParser",
            dependencies: [
                "SkeletonIndexCore",
                "TreeSitterRustGrammar",
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
            ]
        ),
        .target(
            name: "SkeletonCppParser",
            dependencies: [
                "SkeletonIndexCore",
                "TreeSitterCppGrammar",
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
            ]
        ),
        .target(
            name: "SkeletonPythonParser",
            dependencies: [
                "SkeletonIndexCore",
                "TreeSitterPythonGrammar",
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
            ]
        ),
        .target(
            name: "SkeletonJavaParser",
            dependencies: [
                "SkeletonIndexCore",
                "TreeSitterJavaGrammar",
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
            ]
        ),

        // MARK: - Client
        .target(
            name: "SkeletonIndexClient",
            dependencies: ["SkeletonIndexCore"]
        ),

        // MARK: - CLI
        .executableTarget(
            name: "skltn",
            dependencies: [
                "SkeletonIndexCore",
                "SkeletonSwiftParser",
                .target(name: "SkeletonKotlinParser", condition: .when(traits: ["kotlin"])),
                .target(name: "SkeletonTypeScriptParser", condition: .when(traits: ["typescript"])),
                .target(name: "SkeletonGoParser", condition: .when(traits: ["go"])),
                .target(name: "SkeletonZigParser", condition: .when(traits: ["zig"])),
                .target(name: "SkeletonRustParser", condition: .when(traits: ["rust"])),
                .target(name: "SkeletonCppParser", condition: .when(traits: ["cpp"])),
                .target(name: "SkeletonPythonParser", condition: .when(traits: ["python"])),
                .target(name: "SkeletonJavaParser", condition: .when(traits: ["java"])),
            ]
        ),

        // MARK: - Tests
        .testTarget(
            name: "SkeletonIndexCoreTests",
            dependencies: ["SkeletonIndexCore", "SkeletonSwiftParser"]
        ),
        .testTarget(
            name: "ImplementationFingerprintLanguageTests",
            dependencies: [
                "SkeletonIndexCore",
                "SkeletonSwiftParser",
                "SkeletonKotlinParser",
                "SkeletonTypeScriptParser",
                "SkeletonGoParser",
                "SkeletonZigParser",
                "SkeletonRustParser",
                "SkeletonCppParser",
                "SkeletonPythonParser",
                "SkeletonJavaParser",
            ]
        ),
        .testTarget(
            name: "SkeletonKotlinParserTests",
            dependencies: ["SkeletonKotlinParser"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "SkeletonTypeScriptParserTests",
            dependencies: ["SkeletonTypeScriptParser"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "SkeletonGoParserTests",
            dependencies: ["SkeletonGoParser"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "SkeletonZigParserTests",
            dependencies: ["SkeletonZigParser"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "SkeletonRustParserTests",
            dependencies: ["SkeletonRustParser"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "SkeletonCppParserTests",
            dependencies: ["SkeletonCppParser"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "SkeletonPythonParserTests",
            dependencies: ["SkeletonPythonParser"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "SkeletonJavaParserTests",
            dependencies: ["SkeletonJavaParser"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "SkeletonCLIE2ETests"
        ),
    ]
)
