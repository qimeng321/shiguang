// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShiguangMac",
    platforms: [.macOS(.v12)],
    products: [.executable(name: "ShiguangMac", targets: ["ShiguangMac"])],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20")
    ],
    targets: [
        .executableTarget(
            name: "ShiguangMac",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            path: "Sources"
        )
    ]
)
