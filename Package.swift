// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScreenTranslateCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "ScreenTranslateCore", targets: ["ScreenTranslateCore"])],
    targets: [
        .target(name: "ScreenTranslateCore", path: "ScreenTranslate/Core"),
        .testTarget(name: "ScreenTranslateCoreTests", dependencies: ["ScreenTranslateCore"],
                    path: "Tests/ScreenTranslateCoreTests")
    ]
)
