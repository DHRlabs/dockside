// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Dockside",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Dockside", path: "Sources/Dockside")
    ]
)
