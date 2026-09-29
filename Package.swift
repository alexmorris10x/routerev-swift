// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RouteRev",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "RouteRev", targets: ["RouteRev"]),
    ],
    targets: [
        .target(name: "RouteRev"),
        .testTarget(name: "RouteRevTests", dependencies: ["RouteRev"]),
    ]
)
