// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BarShelf",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "BarShelfCore", targets: ["BarShelfCore"]),
        .executable(name: "BarShelfApp", targets: ["BarShelfApp"]),
        .executable(name: "barshelf", targets: ["BarShelfCLI"])
    ],
    targets: [
        .target(
            name: "BarShelfCore",
            path: "Sources/BarShelfCore"
        ),
        .executableTarget(
            name: "BarShelfApp",
            dependencies: ["BarShelfCore"],
            path: "Sources/BarShelf"
        ),
        .executableTarget(
            name: "BarShelfCLI",
            dependencies: ["BarShelfCore"],
            path: "Sources/BarShelfCLI"
        ),
        .testTarget(
            name: "BarShelfCoreTests",
            dependencies: ["BarShelfCore"],
            path: "Tests/BarShelfCoreTests"
        )
    ]
)
