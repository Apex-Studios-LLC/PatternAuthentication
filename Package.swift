// swift-tools-version: 6.0

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
            path: "Sources/PatternAuthentication",
            resources: [.process("Media.xcassets")]
        ),
        .testTarget(
            name: "PatternAuthenticationTests",
            dependencies: ["PatternAuthentication"],
            path: "Tests/PatternAuthenticationTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
