// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "4431_iptv", platforms: [.macOS(.v13)], targets: [
    .binaryTarget(name:"VLCKit",path:"Vendor/VLCKit.xcframework"),
    .binaryTarget(name:"Sparkle",path:"Vendor/Sparkle.xcframework"),
    .executableTarget(name: "Player", dependencies:["VLCKit","Sparkle"], linkerSettings:[.unsafeFlags(["-Xlinker","-rpath","-Xlinker","@executable_path/../Frameworks"])]),
    .testTarget(name: "CatalogTests", dependencies: ["Player"])
])
