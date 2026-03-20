// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenWhatsUI",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "OpenWhatsUI", targets: ["OpenWhatsUI"]),
    ],
    dependencies: [
        .package(path: "../OpenWhatsCore"),
    ],
    targets: [
        .target(
            name: "OpenWhatsUI",
            dependencies: ["OpenWhatsCore"],
            path: "Sources/OpenWhatsUI"
        ),
    ]
)
