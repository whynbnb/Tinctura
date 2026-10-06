// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tinctura",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Tinctura", targets: ["Tinctura"])
    ],
    targets: [
        .executableTarget(
            name: "Tinctura",
            path: "Sources/Tinctura",
            // Xcode app icon catalog; not needed for `swift run`
            exclude: [
                "Resources"
            ]
        )
    ]
)
