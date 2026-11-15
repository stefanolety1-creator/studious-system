// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Msngr",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "MsngrCore",
            targets: ["MsngrCore"]
        ),
        .library(
            name: "MsngrProtocol",
            targets: ["MsngrProtocol"]
        ),
        .library(
            name: "MsngrUI",
            targets: ["MsngrUI"]
        ),
        .executable(
            name: "MsngrApp",
            targets: ["MsngrApp"]
        )
    ],
    dependencies: [
        // Pure standard Apple foundation; no external third-party dependencies required.
    ],
    targets: [
        // MARK: - Core Domain Models, Payloads, and BBCode Formatting
        .target(
            name: "MsngrCore",
            dependencies: [],
            path: "Sources/MsngrCore"
        ),

        // MARK: - MSNP18 Network Engine, SOAP, and Cryptography
        .target(
            name: "MsngrProtocol",
            dependencies: [
                "MsngrCore"
            ],
            path: "Sources/MsngrProtocol"
        ),

        // MARK: - Frutiger Aero SwiftUI User Interface & Theme
        .target(
            name: "MsngrUI",
            dependencies: [
                "MsngrCore",
                "MsngrProtocol"
            ],
            path: "Sources/MsngrUI"
        ),

        // MARK: - Main Application Entry Point
        .executableTarget(
            name: "MsngrApp",
            dependencies: [
                "MsngrCore",
                "MsngrProtocol",
                "MsngrUI"
            ],
            path: "Sources/MsngrApp"
        ),

        // MARK: - Test Targets
        .testTarget(
            name: "MsngrCoreTests",
            dependencies: [
                "MsngrCore"
            ],
            path: "Tests/MsngrCoreTests"
        ),
        .testTarget(
            name: "MsngrProtocolTests",
            dependencies: [
                "MsngrProtocol",
                "MsngrCore"
            ],
            path: "Tests/MsngrProtocolTests"
        ),
        .testTarget(
            name: "MsngrUITests",
            dependencies: [
                "MsngrUI",
                "MsngrCore"
            ],
            path: "Tests/MsngrUITests"
        ),
        .testTarget(
            name: "MsngrIntegrationTests",
            dependencies: [
                "MsngrProtocol",
                "MsngrCore",
                "MsngrUI"
            ],
            path: "Tests/MsngrIntegrationTests"
        )
    ]
)
