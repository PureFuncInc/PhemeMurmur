// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PhemeMurmur",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "PhemeMurmur",
            path: "Sources/PhemeMurmur"
        )
    ]
)
