// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SamGlasses",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "SamGlasses",
            targets: ["SamGlasses"]),
    ],
    dependencies: [
        // No external dependencies to keep it lightweight
        // All networking will use URLSession
        // All UI will use SwiftUI
    ],
    targets: [
        .target(
            name: "SamGlasses",
            dependencies: [],
            path: "Sources/SamGlasses",
            resources: []
        ),
        .testTarget(
            name: "SamGlassesTests",
            dependencies: ["SamGlasses"]),
    ]
)