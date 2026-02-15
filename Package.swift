// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "swift-skeleton",
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
    ],
    dependencies: [
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter.git", from: "0.9.0"),
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
        .testTarget(
            name: "SkeletonIndexCoreTests",
            dependencies: ["SkeletonIndexCore", "SkeletonSwiftParser"]
        ),
    ]
)
