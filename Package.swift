// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "4431_iptv", platforms: [.macOS(.v13)], targets: [
    .binaryTarget(name:"VLCKit",path:"Vendor/VLCKit.xcframework"),
    .executableTarget(name: "Player", dependencies:["VLCKit"]),
    .testTarget(name: "CatalogTests", dependencies: ["Player"])
])
