// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TouchBarApp",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "TouchBarApp",
            path: "Sources/TouchBarApp",
            // Swift 5 language mode: AppKit + private-API bridging predates strict
            // concurrency annotations, and everything here is main-thread bound anyway.
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
