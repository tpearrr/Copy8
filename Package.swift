// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Copy8",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Copy8",
            path: "Sources/Copy8",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
