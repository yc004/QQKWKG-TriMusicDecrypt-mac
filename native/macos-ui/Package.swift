// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QKKDecryptUI",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "QKKDecrypt-UI", targets: ["QKKDecryptUI"]),
    ],
    targets: [
        .executableTarget(
            name: "QKKDecryptUI",
            path: "Sources"
        ),
    ]
)
