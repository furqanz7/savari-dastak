// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DastakUI",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DastakUI", targets: ["DastakUI"])
    ],
    dependencies: [
        .package(path: "../DastakDomain"),
        .package(path: "../MarketplaceDesignSystem"),
        .package(path: "../MarketplaceFoundation"),
        .package(path: "../MarketplaceInfrastructure"),
        .package(url: "https://github.com/razorpay/razorpay-pod.git", exact: "1.5.7")
    ],
    targets: [
        .target(
            name: "DastakUI",
            dependencies: [
                "DastakDomain",
                "MarketplaceDesignSystem",
                "MarketplaceFoundation",
                "MarketplaceInfrastructure",
                .product(name: "RazorpayCheckout", package: "razorpay-pod")
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "DastakUITests",
            dependencies: [
                "DastakUI",
                "MarketplaceFoundation",
                "MarketplaceInfrastructure"
            ]
        )
    ]
)
