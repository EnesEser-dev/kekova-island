// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KekovaIsland",
    platforms: [.macOS("15.0")],
    targets: [
        .executableTarget(name: "KekovaIsland", path: "Sources/KekovaIsland")
    ]
)
