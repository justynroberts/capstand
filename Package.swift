// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Capstand",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Capstand",
            path: "Sources/Capstand",
            // Not a SwiftPM resource: Bundle.module bakes this machine's .build
            // path into the binary. bundle.sh copies the font in by hand.
            exclude: ["Resources"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
