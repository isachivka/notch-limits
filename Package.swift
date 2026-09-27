// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "NotchLimits",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "NotchLimitsCore",
            swiftSettings: [.enableUpcomingFeature("BareSlashRegexLiterals")]
        ),
        .executableTarget(name: "NotchLimits", dependencies: ["NotchLimitsCore"]),
        .testTarget(
            name: "NotchLimitsCoreTests",
            dependencies: ["NotchLimitsCore"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
