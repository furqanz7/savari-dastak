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
        .package(path: "../DastakLiveTracking"),
        .package(path: "../DastakDomain"),
        .package(path: "../MarketplaceDesignSystem"),
        .package(path: "../MarketplaceFoundation"),
        .package(path: "../MarketplaceInfrastructure")
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
                "DastakLiveTracking",
                "DastakDomain",
                "MarketplaceDesignSystem",
                "MarketplaceFoundation",
                "MarketplaceInfrastructure"
            ],
            resources: [.process("Resources")]
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
