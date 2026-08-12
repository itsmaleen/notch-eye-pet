// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchEyePet",
    platforms: [
        // DynamicNotchKit's floor. Head pitch (VNFaceObservation.pitch) needs 12.0+,
        // which only matters once the opt-in camera lane lands.
        .macOS(.v13)
    ],
    products: [
        .executable(name: "NotchEyePet", targets: ["NotchEyePet"]),
        .library(name: "EyePetCore", targets: ["EyePetCore"])
    ],
    dependencies: [
        // MIT. Deliberately NOT boring.notch, which is GPL-3 and would infect this app.
        .package(url: "https://github.com/MrKai77/DynamicNotchKit.git", from: "1.1.0")
    ],
    targets: [
        // Pure logic: presence detection + break accrual. No UI, so it is testable
        // headlessly and can be exercised without ever showing a window.
        .target(
            name: "EyePetCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "NotchEyePet",
            dependencies: [
                "EyePetCore",
                .product(name: "DynamicNotchKit", package: "DynamicNotchKit")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "EyePetCoreTests",
            dependencies: ["EyePetCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
