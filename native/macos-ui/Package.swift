// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QKKDecryptUI",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "QKKDecrypt-UI", targets: ["QKKDecryptUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jaywcjlove/PermissionFlow.git", exact: "2.11.2"),
        .package(
            url: "https://github.com/inket/FullDiskAccess.git",
            revision: "51d8465ad2babb0710996a39fe183d27dcd72634"
        ),
    ],
    targets: [
        .executableTarget(
            name: "QKKDecryptUI",
            dependencies: [
                .product(name: "FullDiskAccess", package: "FullDiskAccess"),
                .product(name: "PermissionFlow", package: "PermissionFlow"),
            ],
            path: "Sources"
        ),
    ]
)
