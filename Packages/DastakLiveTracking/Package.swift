// swift-tools-version: 6.0
import PackageDescription

let package = Package(name: "DastakLiveTracking", platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "DastakLiveTracking", targets: ["DastakLiveTracking"])],
    targets: [.target(name: "DastakLiveTracking"),
              .testTarget(name: "DastakLiveTrackingTests", dependencies: ["DastakLiveTracking"])])
