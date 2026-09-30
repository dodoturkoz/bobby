// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Bobby",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BobbyCore", targets: ["BobbyCore"]),
        .executable(name: "Bobby", targets: ["Bobby"])
    ],
    targets: [
        .target(name: "BobbyCore"),
        .executableTarget(name: "Bobby", dependencies: ["BobbyCore"]),
        .testTarget(name: "BobbyCoreTests", dependencies: ["BobbyCore"])
    ]
)
