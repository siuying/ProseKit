// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ProseKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "ProseModel", targets: ["ProseModel"]),
        .library(name: "ProseEditor", targets: ["ProseEditor"]),
        .library(name: "ProseKitYjs", targets: ["ProseKitYjs"]),
    ],
    dependencies: [
        // Local sibling checkout should match SwiftYrs v0.3.0; CI checks out
        // that tag before building the local xcframework.
        .package(path: "../SwiftYrs"),
    ],
    targets: [
        .target(name: "ProseModel"),
        .target(
            name: "ProseEditor",
            dependencies: ["ProseModel"]
        ),
        .target(
            name: "ProseKitYjs",
            dependencies: [
                "ProseEditor",
                .product(name: "SwiftYrs", package: "SwiftYrs"),
            ]
        ),
        .testTarget(
            name: "ProseModelTests",
            dependencies: ["ProseModel"]
        ),
        .testTarget(
            name: "ProseEditorTests",
            dependencies: ["ProseEditor", "ProseModel"],
            resources: [
                .copy("Resources/last_question.txt")
            ]
        ),
        .testTarget(
            name: "ProseKitYjsTests",
            dependencies: [
                "ProseKitYjs",
                "ProseEditor",
                "ProseModel",
                .product(name: "SwiftYrs", package: "SwiftYrs"),
            ]
        ),
    ]
)
