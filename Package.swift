// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Prose",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "ProseModel", targets: ["ProseModel"]),
        .library(name: "ProseEditor", targets: ["ProseEditor"]),
    ],
    targets: [
        .target(name: "ProseModel"),
        .target(
            name: "ProseEditor",
            dependencies: ["ProseModel"]
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
    ]
)
