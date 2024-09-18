// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "PatternAuthentication",
    platforms: [
        .iOS(.v15),
    ],
    products: [
        .library(
            name: "PatternAuthentication",
            targets: ["PatternAuthentication"]
        ),
    ],
    targets: [
        .target(
            name: "PatternAuthentication",
            dependencies: [],
            path: "Sources",
            exclude: ["Images"],
            resources: [.process("Media.xcassets")]
        ),
    ]
)
