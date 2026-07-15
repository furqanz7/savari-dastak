// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DastakDomain",
    platforms: [.iOS(.v17)],
    dependencies: [
        .package(path: "../MarketplaceFoundation")
    ]
)
