// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DastakUI",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DastakUI", targets: ["DastakUI"]),
        .library(name: "DastakLaunchUI", targets: ["DastakLaunchUI"])
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
            name: "DastakLaunchUI",
            dependencies: ["MarketplaceDesignSystem"],
            resources: [.process("Resources")]
        ),
        .target(
            name: "DastakUI",
            dependencies: [
                "DastakDomain",
                "MarketplaceDesignSystem",
                "MarketplaceFoundation",
                "MarketplaceInfrastructure",
                .product(
                    name: "RazorpayCheckout",
                    package: "razorpay-pod",
                    condition: .when(platforms: [.iOS])
                )
            ]
        ),
        .testTarget(
            name: "DastakUITests",
            dependencies: [
                "DastakUI",
                "DastakLaunchUI",
                "MarketplaceFoundation",
                "MarketplaceInfrastructure"
            ]
        )
    ]
)
