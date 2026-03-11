// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Vaaka",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Vaaka", targets: ["Vaaka"])
    ],
    targets: [
        .target(
            name: "VaakaLib",
            dependencies: [],
            path: "Sources/VaakaLib",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "Vaaka",
            dependencies: ["VaakaLib"],
            path: "Sources/Vaaka",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "VaakaTests",
            dependencies: ["VaakaLib"],
            path: "Tests/VaakaTests"
        )
    ]
)
