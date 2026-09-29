// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Wheedgets",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Wheedgets", targets: ["Wheedgets"])
    ],
    targets: [
        // Pure, UI-free logic: settings model, key routing rules, sound synthesis.
        .target(name: "WheedgetsCore"),
        // The menu bar app: shared services (audio, keyboard) and the fidget modules.
        .executableTarget(
            name: "Wheedgets",
            dependencies: ["WheedgetsCore"]
        ),
        .testTarget(
            name: "WheedgetsCoreTests",
            dependencies: ["WheedgetsCore"]
        ),
        // Tests for app-side code that needs no UI (audio decoding, pack loading).
        .testTarget(
            name: "WheedgetsTests",
            dependencies: ["Wheedgets", "WheedgetsCore"]
        )
    ]
)
