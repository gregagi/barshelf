// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BarShelf",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "BarShelfCore", targets: ["BarShelfCore"]),
        .executable(name: "BarShelf", targets: ["BarShelf"]),
        .executable(name: "barshelf", targets: ["barshelf"])
    ],
    targets: [
        .target(
            name: "BarShelfCore",
            path: "Sources/BarShelfCore"
        ),
        .executableTarget(
            name: "BarShelf",
            dependencies: ["BarShelfCore"],
            path: "Sources/BarShelf"
        ),
        .executableTarget(
            name: "barshelf",
            dependencies: ["BarShelfCore"],
            path: "Sources/barshelf"
        ),
        .testTarget(
            name: "BarShelfCoreTests",
            dependencies: ["BarShelfCore"],
            path: "Tests/BarShelfCoreTests"
        )
    ]
)
