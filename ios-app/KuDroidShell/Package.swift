// swift-tools-version: 6.0
import PackageDescription
import Foundation

let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let angleFrameworkDir = ProcessInfo.processInfo.environment["KUDROID_ANGLE_FRAMEWORK_DIR"]
    ?? "../../third_party/ANGLE/lib"

let package = Package(
    name: "KuDroidShell",
    platforms: [
        .iOS(.v15),
    ],
    products: [
        .library(
            name: "KuDroidShell",
            targets: ["KuDroidShell"]
        ),
        .library(name: "KuDroidJITHelper", targets: ["KuDroidJITHelper"]),
    ],
    targets: [
        .target(
            name: "KuDroidShell",
            dependencies: [
                "JITSupport",
                "JITProtocol",
                "MoltenVK",
                "libEGL",
                "libGLESv2",
            ],
            path: ".",
            sources: [
                "KuDroidApp.swift",
                "ContentView.swift",
                "AppsView.swift",
                "AppIcons.swift",
                "PermissionsView.swift",
                "HostLifecycle.swift",
                "RuntimeTools.swift",
                "NativeRunner.swift",
                "APKExport.swift",
                "AppActions.swift",
                "DocumentImport.swift",
                "ReverseHistory.swift",
                "IOSDiagnostics.swift",
                "EcCryptoBridge.swift",
                "WebViewBridge.swift",
                "BrowserData.swift",
                "CameraBridge.swift",
                "MediaPlayerBridge.swift",
                "SensorBridge.swift",
                "NetworkBridge.swift",
                "ThermalBridge.swift",
                "GuestTouchState.swift",
                "ImmediateScrollTouches.swift",
                "ShellSettings.swift",
                "AppMemorySettings.swift",
                "MemoryBudgetPolicy.swift",
                "MicroG.swift",
                "SharedPackageRemoval.swift",
                "JITSetup.swift",
                "JITStartup.swift",
                "JITTutorial.swift",
                "PairingNotifications.swift",
                "JITBundleConfiguration.swift",
                "JITReadiness.swift",
                "JITStatusModel.swift",
                "JITLaunchButton.swift",
                "DocumentPicker.swift",
            ],
            resources: [.copy("THIRD_PARTY_NOTICES.txt"), .copy("Resources/licenses"), .copy("Resources/microg")],
            swiftSettings: [
                .unsafeFlags([
                    "-import-objc-header", "\(packageDir)/kudroid_bridge.h",
                    "-I", "\(packageDir)"
                ]),
            ],
            linkerSettings: [
                .linkedLibrary("kudroid_core_combined"),
                .linkedLibrary("kudroid_pairing"),
                .linkedLibrary("z"),
                .linkedLibrary("resolv"),
                .linkedLibrary("sqlite3"),
                .linkedLibrary("c++"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("Foundation"),
                .linkedFramework("UIKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOSurface"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("Network"),
                .linkedFramework("Security"),
                .unsafeFlags(["-L", "\(packageDir)/libs", "-Xlinker", "-export_dynamic"])
            ]
        ),
        .target(
            name: "JITSupport",
            path: "JITSupport",
            publicHeadersPath: "include",
            cSettings: [.unsafeFlags(["-fobjc-arc"])],
            cxxSettings: [.unsafeFlags(["-fobjc-arc", "-I", "\(packageDir)/../../include"])],
            linkerSettings: [.linkedFramework("Security")]
        ),
        .target(name: "JITNotifications", path: "JITNotifications", publicHeadersPath: "include"),
        .target(name: "JITProtocol", dependencies: ["JITNotifications"], path: "JITProtocol"),
        .target(
            name: "KuDroidJITHelper",
            dependencies: ["JITProtocol", "StikJIT"],
            path: "JITHelper",
            exclude: ["Info.plist"],
            sources: ["JITService.swift"],
            resources: [.copy("jit-bootstrap.js")],
            swiftSettings: [.unsafeFlags(["-application-extension"])],
            linkerSettings: [.linkedLibrary("swiftCore"),
                             .unsafeFlags(["-Xlinker", "-ObjC",
                                           "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../../Frameworks"])]
        ),
        .binaryTarget(name: "StikJIT", path: "../../third_party/StikJIT/StikJIT.xcframework"),
        .binaryTarget(
            name: "MoltenVK",
            path: "../../third_party/MoltenVK/MoltenVK/dynamic/MoltenVK.xcframework"
        ),
        .binaryTarget(
            name: "libEGL",
            path: "\(angleFrameworkDir)/libEGL.xcframework"
        ),
        .binaryTarget(
            name: "libGLESv2",
            path: "\(angleFrameworkDir)/libGLESv2.xcframework"
        ),
    ],
    swiftLanguageModes: [.v5],
    cxxLanguageStandard: .cxx17
)
