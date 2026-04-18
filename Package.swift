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
        // SecureMem - mlock-backed memory for password protection (never swapped to disk)
        .target(
            name: "SecureMem",
            dependencies: [],
            path: "Sources/SecureMem",
            publicHeadersPath: "include"
        ),
        // Aplicación principal con UI SwiftUI
        .executableTarget(
            name: "MAI",
            dependencies: ["CEFWrapper", "SecureMem"],
            path: "Sources/MAI",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"]),
                .enableExperimentalFeature("SymbolLinkageMarkers")
            ],
            linkerSettings: [
                .linkedFramework("CoreML"),
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks",
                ]),
                // Release-only anti-RE hardening:
                //  -dead_strip removes unreferenced symbols (reduces attack surface + binary size)
                //  -u _ptrace forces linker to keep ptrace import alive (used by PT_DENY_ATTACH)
                .unsafeFlags([
                    "-Xlinker", "-dead_strip",
                    "-Xlinker", "-u", "-Xlinker", "_ptrace",
                ], .when(configuration: .release))
            ]
        )
    ],
    cxxLanguageStandard: .cxx17
)
