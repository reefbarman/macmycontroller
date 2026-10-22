// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacMyController",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacMyController", targets: ["MacMyController"]),
    ],
    targets: [
        // Pure, platform-light logic. Everything here is unit tested.
        .target(name: "MacMyControllerCore"),
        // AppKit / GameController / CGEvent integration.
        .executableTarget(
            name: "MacMyController",
            dependencies: ["MacMyControllerCore"]
        ),
        .testTarget(
            name: "MacMyControllerCoreTests",
            dependencies: ["MacMyControllerCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
