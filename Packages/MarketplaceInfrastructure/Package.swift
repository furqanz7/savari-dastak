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
        .package(url: "https://github.com/supabase/supabase-swift.git", exact: "2.37.0"),
        .package(url: "https://github.com/PhoneNumberKit/PhoneNumberKit.git", exact: "5.0.7")
    ],
    targets: [
        .target(
            name: "MarketplaceInfrastructure",
            dependencies: [
                "MarketplaceFoundation",
                "MarketplaceDesignSystem",
                .product(name: "PhoneNumberKit", package: "PhoneNumberKit"),
                .product(name: "Supabase", package: "supabase-swift")
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "MarketplaceInfrastructureTests",
            dependencies: [
                "MarketplaceInfrastructure",
                "MarketplaceFoundation",
                .product(name: "Supabase", package: "supabase-swift")
            ]
        )
    ]
)
