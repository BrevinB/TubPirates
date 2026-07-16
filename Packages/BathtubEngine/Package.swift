// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BathtubEngine",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "BathtubEngine", targets: ["BathtubEngine"])
    ],
    targets: [
        .target(name: "BathtubEngine"),
        .testTarget(name: "BathtubEngineTests", dependencies: ["BathtubEngine"]),
    ],
    swiftLanguageModes: [.v6]
)
