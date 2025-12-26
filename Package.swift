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
            resources: [.copy("../Resources/whitelist.json")]
        ),
    ]
)
