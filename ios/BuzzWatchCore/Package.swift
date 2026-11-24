// swift-tools-version: 5.9
import PackageDescription

// Everything the watch app does that is not a screen: Nostr signing, the
// relay connection, signed media downloads and markdown. Plain Swift, so its
// tests run on a Mac with `swift test`, no simulator needed.
let package = Package(
    name: "BuzzWatchCore",
    platforms: [.watchOS(.v10), .iOS(.v16), .macOS(.v13)],
    products: [.library(name: "BuzzWatchCore", targets: ["BuzzWatchCore"])],
    dependencies: [
        .package(url: "https://github.com/21-DOT-DEV/swift-secp256k1", exact: "0.25.1"),
    ],
    targets: [
        .target(name: "BuzzWatchCore", dependencies: [.product(name: "P256K", package: "swift-secp256k1")]),
        .testTarget(name: "BuzzWatchCoreTests", dependencies: ["BuzzWatchCore"]),
    ]
)
