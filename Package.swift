// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftColor",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SwiftColor", targets: ["SwiftColor"])
    ],
    targets: [
        .executableTarget(
            name: "SwiftColor",
            path: "Sources/SwiftColor"
        )
    ]
)
