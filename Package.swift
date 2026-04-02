// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MBAgentKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "MBAgentKit", targets: ["MBAgentKit"]),
        .library(name: "MBAgentKitUI", targets: ["MBAgentKitUI"]),
        .library(name: "MBAgentKitOpenAI", targets: ["MBAgentKitOpenAI"])
    ],
    dependencies: [
        .package(url: "https://github.com/MacPaw/OpenAI", from: "0.4.7")
    ],
    targets: [
        // Core: zero external dependencies
        .target(
            name: "MBAgentKit",
            dependencies: [],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),

        // UI: SwiftUI components for Agent runtime display
        .target(
            name: "MBAgentKitUI",
            dependencies: ["MBAgentKit"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),

        // OpenAI: MacPaw/OpenAI SDK integration (optional)
        .target(
            name: "MBAgentKitOpenAI",
            dependencies: [
                "MBAgentKit",
                .product(name: "OpenAI", package: "OpenAI")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),

        // Tests
        .testTarget(
            name: "MBAgentKitTests",
            dependencies: ["MBAgentKit"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
