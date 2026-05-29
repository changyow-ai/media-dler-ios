// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MediaDlerCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "MediaDlerCore", targets: ["MediaDlerCore"]),
    ],
    targets: [
        .target(name: "MediaDlerCore"),
        .testTarget(name: "MediaDlerCoreTests", dependencies: ["MediaDlerCore"]),
    ]
)
