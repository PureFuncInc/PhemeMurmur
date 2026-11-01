// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PhemeMurmur",
    platforms: [.macOS(.v26)],
    targets: [
        .target(
            name: "PhemeMurmurCore",
            path: "Sources/PhemeMurmurCore"
        ),
        .executableTarget(
            name: "PhemeMurmur",
            dependencies: ["PhemeMurmurCore"],
            path: "Sources/PhemeMurmur"
        ),
    ]
)
