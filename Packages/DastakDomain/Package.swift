// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DastakDomain",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "DastakDomain", targets: ["DastakDomain"])
    ],
    dependencies: [
        .package(path: "../MarketplaceFoundation")
    ],
    targets: [
        .target(
            name: "DastakDomain",
            dependencies: ["MarketplaceFoundation"]
        ),
        .testTarget(
            name: "DastakDomainTests",
            dependencies: ["DastakDomain", "MarketplaceFoundation"]
        )
    ]
)
