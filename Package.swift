// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotFancyZones",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "NotFancyZones", targets: ["NotFancyZones"])],
    targets: [
        .target(name: "ZonesCore"),
        .executableTarget(name: "NotFancyZones", dependencies: ["ZonesCore"]),
        .executableTarget(name: "ZoneTestWindow"),
        .executableTarget(name: "ZonesCoreTests", dependencies: ["ZonesCore"], path: "Tests/ZonesCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
