// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SDBackupApp",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "SDBackupApp",
            path: "Sources"
        )
    ]
)
