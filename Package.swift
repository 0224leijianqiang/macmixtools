// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SSHTools",
    defaultLocalization: "en",
    platforms: [
        .macOS("15.0")
    ],
    products: [
        .executable(name: "SSHTools", targets: ["SSHTools"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/mysql-kit.git", from: "4.0.0"),
        .package(url: "https://github.com/orlandos-nl/Citadel.git", from: "0.11.1"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.5.1"),
        .package(url: "https://github.com/swift-server/RediStack.git", from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .executableTarget(
            name: "SSHTools",
            dependencies: [
                .product(name: "MySQLKit", package: "mysql-kit"),
                .product(name: "Citadel", package: "Citadel"),
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "RediStack", package: "RediStack"),
            ],
            path: "Sources/SSHTools",
            resources: [
                .process("AppIcon.icns"),
                .process("Resources")
            ]
        ),
    ]
)
