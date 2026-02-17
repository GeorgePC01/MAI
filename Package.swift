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
        // CEF Wrapper - Objective-C++ bridge to Chromium Embedded Framework
        // Uses dynamic loading (dlopen) instead of direct framework linking (required on macOS)
        .target(
            name: "CEFWrapper",
            dependencies: [],
            path: "Sources/CEFWrapper",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("../../Frameworks/CEF"),
                .define("WRAPPING_CEF_SHARED", to: "1"),
            ],
            cxxSettings: [
                .headerSearchPath("../../Frameworks/CEF"),
                .define("WRAPPING_CEF_SHARED", to: "1"),
            ],
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreImage")
            ]
        ),
        // Aplicación principal con UI SwiftUI
        .executableTarget(
            name: "MAI",
            dependencies: ["CEFWrapper"],
            path: "Sources/MAI",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks",
                ])
            ]
        )
    ],
    cxxLanguageStandard: .cxx17
)
