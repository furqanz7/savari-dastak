// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SavariDomain",
    platforms: [.iOS(.v17)],
    dependencies: [
        .package(path: "../MarketplaceFoundation")
    ]
)
