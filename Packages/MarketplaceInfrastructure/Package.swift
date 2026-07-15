// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MarketplaceInfrastructure",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "MarketplaceInfrastructure", targets: ["MarketplaceInfrastructure"])
    ],
    dependencies: [
        .package(path: "../MarketplaceFoundation")
    ],
    targets: [
        .target(
            name: "MarketplaceInfrastructure",
            dependencies: ["MarketplaceFoundation"]
        ),
        .testTarget(
            name: "MarketplaceInfrastructureTests",
            dependencies: ["MarketplaceInfrastructure", "MarketplaceFoundation"]
        )
    ]
)
