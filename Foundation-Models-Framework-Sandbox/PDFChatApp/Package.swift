// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PDFChatApp",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "PDFChatApp",
            targets: ["PDFChatApp"]),
    ],
    dependencies: [
        // Foundation Models Framework is included in the system
    ],
    targets: [
        .target(
            name: "PDFChatApp",
            dependencies: [],
            path: "Sources"
        ),
        .testTarget(
            name: "PDFChatAppTests",
            dependencies: ["PDFChatApp"],
            path: "Tests"
        ),
    ]
)