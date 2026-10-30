// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ostracon",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Ostracon", targets: ["Ostracon"]),
        .executable(name: "ostracon-mcp", targets: ["OstraconMCP"]),
        .library(name: "OstraconCore", targets: ["OstraconCore"])
    ],
    targets: [
        .target(
            name: "OstraconCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "Ostracon",
            dependencies: ["OstraconCore"]
        ),
        .executableTarget(
            name: "OstraconMCP",
            dependencies: ["OstraconCore"]
        ),
        .testTarget(
            name: "OstraconCoreTests",
            dependencies: ["OstraconCore"]
        ),
        .testTarget(
            name: "OstraconMCPTests",
            dependencies: ["OstraconMCP", "OstraconCore"]
        ),
        .testTarget(
            name: "OstraconTests",
            dependencies: ["Ostracon", "OstraconCore"]
        )
    ]
)
