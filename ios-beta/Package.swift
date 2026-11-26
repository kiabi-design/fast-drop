// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FastDrop",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "FastDropCore", targets: ["FastDropCore"]),
        .executable(name: "FastDropApp", targets: ["FastDropApp"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "FastDropCore",
            dependencies: [],
            resources: [
                .process("Resources/Shaders.metallib")
            ]
        ),
        .executableTarget(
            name: "FastDropApp",
            dependencies: ["FastDropCore"]
        ),
        .testTarget(
            name: "FastDropTests",
            dependencies: ["FastDropCore"]
        )
    ]
)