// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MarketplaceFoundation",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "MarketplaceFoundation", targets: ["MarketplaceFoundation"])
    ],
    targets: [
        .target(name: "MarketplaceFoundation"),
        .testTarget(
            name: "MarketplaceFoundationTests",
            dependencies: ["MarketplaceFoundation"]
        )
    ]
)
