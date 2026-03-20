// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenWhatsCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "OpenWhatsCore", targets: ["OpenWhatsCore"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "OpenWhatsCore",
            dependencies: [],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "OpenWhatsCoreTests",
            dependencies: ["OpenWhatsCore"]
        ),
    ]
)
