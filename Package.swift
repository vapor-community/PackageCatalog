// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "PackageCatalogAPI",
    dependencies: [
        .package(url: "https://github.com/vapor/vapor", from: "3.0.0-rc.2.8.1"),
        .package(url: "https://github.com/vapor/auth.git", from: "2.0.0-rc")
    ],
    targets: [
        .target(name: "App", dependencies: ["Vapor", "Authentication"]),
        .target(name: "Run", dependencies: ["App"]),
        .testTarget(name: "AppTests", dependencies: ["App"])
    ]
)
