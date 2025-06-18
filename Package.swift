// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Base dependencies needed on all platforms
var dependencies: [Package.Dependency] = [
    .package(url: "https://github.com/apple/swift-system.git", from: "1.5.0"),
    .package(url: "https://github.com/apple/swift-log.git", from: "1.6.3"),
    .package(url: "https://github.com/loopwork-ai/EventSource", from: "1.1.1"),
]

// Target dependencies needed on all platforms
var targetDependencies: [Target.Dependency] = [
    .product(name: "SystemPackage", package: "swift-system"),
    .product(name: "Logging", package: "swift-log"),
    .product(name: "EventSource", package: "eventsource"),
]

let package = Package(
    name: "mcpSwift",
    platforms: [
        .macOS("14.0"),
        .macCatalyst("17.0"),
        .iOS("17.0"),
        .watchOS("10.0"),
        .tvOS("17.0"),
        .visionOS("2.0"),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "MCPSwift",
            targets: ["MCPSwift"])
    ],
    dependencies: dependencies,
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "MCPSwift",
            dependencies: targetDependencies),
        .testTarget(
            name: "MCPSwiftTests",
            dependencies: ["MCPSwift"] + targetDependencies),
    ]
)
