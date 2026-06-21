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
        .package(url: "https://github.com/siuying/SwiftYrs", from: "0.1.0"),
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
