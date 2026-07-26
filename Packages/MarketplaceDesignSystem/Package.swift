// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MarketplaceDesignSystem",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(
            name: "MarketplaceDesignSystem",
            targets: ["MarketplaceDesignSystem"]
        )
    ],
    targets: [
        .target(name: "MarketplaceDesignSystem"),
        .testTarget(
            name: "MarketplaceDesignSystemTests",
            dependencies: ["MarketplaceDesignSystem"]
        )
    ]
)
