// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Vaaka",
    platforms: [ .macOS(.v14) ],
    products: [
        .executable(name: "Vaaka", targets: ["Vaaka"]),
    ],
    targets: [
        .executableTarget(
            name: "Vaaka",
            path: "Sources/Vaaka",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "VaakaTests",
            dependencies: ["Vaaka"],
            path: "Tests/VaakaTests"
        )
    ]
)
