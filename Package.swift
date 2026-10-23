// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "opaq",
    platforms: [
        .macOS(.v26)
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
            path: "Sources/opaq",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "opaqTests",
            dependencies: ["opaq"],
            path: "Tests/opaqTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
    ]
)
