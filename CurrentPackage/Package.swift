// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CurrentFeature",
    platforms: [.macOS(.v14)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "CurrentFeature",
            targets: ["CurrentFeature"]
        ),
        .executable(
            name: "CurrentFeatureChecks",
            targets: ["CurrentFeatureChecks"]
        ),
        .executable(name: "CurrentUIProbe", targets: ["CurrentUIProbe"]),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "CurrentFeature"
        ),
        .executableTarget(
            name: "CurrentFeatureChecks",
            dependencies: [
                "CurrentFeature"
            ]
        ),
        .executableTarget(name: "CurrentUIProbe", dependencies: ["CurrentFeature"]),
        .testTarget(
            name: "CurrentFeatureTests",
            dependencies: [
                "CurrentFeature"
            ]
        ),
    ]
)
