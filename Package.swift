// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Transcriberino",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.1"),
    ],
    targets: [
        .executableTarget(
            name: "Transcriberino",
            dependencies: ["HotKey"],
            path: "Transcriberino",
            exclude: ["Info.plist"],
            resources: [.process("Assets.xcassets")]
        ),
    ]
)
