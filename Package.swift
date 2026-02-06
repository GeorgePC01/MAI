// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MAI",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "MAI",
            targets: ["MAI"]
        )
    ],
    dependencies: [],
    targets: [
        // Aplicación principal con UI SwiftUI
        .executableTarget(
            name: "MAI",
            dependencies: [],
            path: "Sources/MAI",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)
