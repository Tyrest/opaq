// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "opaq",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "opaq",
            targets: ["opaq"]
        ),
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "opaq",
            dependencies: [],
            path: "Sources/opaq"
        ),
    ]
)
