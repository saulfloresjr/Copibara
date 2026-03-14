// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Copibara",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Copibara",
            path: "Sources",
            resources: [
                .copy("Resources")
            ]
        )
    ]
)
