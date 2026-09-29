// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BathtubEngine",
    // Required for BathtubUI's shared string catalog.
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "BathtubEngine", targets: ["BathtubEngine"]),
        .library(name: "MessageGameCore", targets: ["MessageGameCore"]),
        .library(name: "BathtubArena", targets: ["BathtubArena"]),
        .library(name: "BathtubUI", targets: ["BathtubUI"])
    ],
    targets: [
        .target(name: "BathtubEngine"),
        .target(name: "MessageGameCore", dependencies: ["BathtubEngine"]),
        .target(name: "BathtubArena", dependencies: ["BathtubEngine", "BathtubUI"]),
        .target(
            name: "BathtubUI",
            dependencies: ["BathtubEngine"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "BathtubEngineTests", dependencies: ["BathtubEngine"]),
        .testTarget(name: "MessageGameCoreTests", dependencies: ["MessageGameCore", "BathtubEngine"]),
    ],
    swiftLanguageModes: [.v6]
)
