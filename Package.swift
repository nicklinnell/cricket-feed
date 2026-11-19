// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CricketFeed",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "CricketFeed", path: "Sources/CricketFeed"),
        .testTarget(name: "CricketFeedTests", dependencies: ["CricketFeed"], path: "Tests/CricketFeedTests"),
    ]
)
