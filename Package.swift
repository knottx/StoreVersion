// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StoreVersion",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
    ],
    products: [
        .library(name: "StoreVersion", targets: ["StoreVersion"]),
    ],
    targets: [
        .target(name: "StoreVersion"),
        .testTarget(name: "StoreVersionTests", dependencies: ["StoreVersion"]),
    ],
    swiftLanguageModes: [.v6]
)
