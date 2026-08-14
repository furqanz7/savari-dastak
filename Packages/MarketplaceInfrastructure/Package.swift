// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MarketplaceInfrastructure",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "MarketplaceInfrastructure", targets: ["MarketplaceInfrastructure"])
    ],
    dependencies: [
        .package(path: "../MarketplaceFoundation"),
        .package(path: "../MarketplaceDesignSystem"),
        .package(url: "https://github.com/supabase/supabase-swift.git", exact: "2.37.0")
    ],
    targets: [
        .target(
            name: "MarketplaceInfrastructure",
            dependencies: [
                "MarketplaceFoundation",
                "MarketplaceDesignSystem",
                .product(name: "Supabase", package: "supabase-swift")
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "MarketplaceInfrastructureTests",
            dependencies: ["MarketplaceInfrastructure", "MarketplaceFoundation"]
        )
    ]
)
