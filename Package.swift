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
            name: "SkeletonIndexClient",
            targets: ["SkeletonIndexClient"]
        ),
        .executable(
            name: "skeletonindexd",
            targets: ["skeletonindexd"]
        ),
        .executable(
            name: "skeletonindex",
            targets: ["skeletonindex"]
        ),
        .executable(
            name: "skeletonindex-mcp",
            targets: ["skeletonindex-mcp"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter.git", from: "0.9.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.7.1"),
    ],
    targets: [
        .target(
            name: "TreeSitterSwiftGrammar",
            path: "Sources/TreeSitterSwiftGrammar",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("."),
            ]
        ),
        .target(
            name: "SkeletonIndexCore"
        ),
        .target(
            name: "SkeletonSwiftParser",
            dependencies: [
                "SkeletonIndexCore",
                "TreeSitterSwiftGrammar",
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
            ]
        ),
        .target(
            name: "SkeletonIndexClient",
            dependencies: ["SkeletonIndexCore"]
        ),
        .executableTarget(
            name: "skeletonindexd",
            dependencies: ["SkeletonIndexCore", "SkeletonSwiftParser"]
        ),
        .executableTarget(
            name: "skeletonindex",
            dependencies: ["SkeletonIndexClient", "SkeletonSwiftParser"]
        ),
        .executableTarget(
            name: "skeletonindex-mcp",
            dependencies: [
                "SkeletonIndexCore",
                "SkeletonSwiftParser",
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),
        .testTarget(
            name: "SkeletonIndexCoreTests",
            dependencies: ["SkeletonIndexCore", "SkeletonSwiftParser"]
        ),
    ]
)
