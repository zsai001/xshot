// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "XShot",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "XShot", targets: ["XShot"])
    ],
    targets: [
        .executableTarget(
            name: "XShot",
            path: "Sources/XShot",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("CoreImage"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("Metal"),
                .linkedFramework("Carbon"),
                .linkedFramework("ImageIO"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("Vision"),
                .linkedFramework("StoreKit")
            ]
        ),
        .testTarget(
            name: "XShotTests",
            dependencies: ["XShot"],
            path: "Tests/XShotTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
