// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Leaf",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Leaf", targets: ["Leaf"])],
    targets: [
        .target(name: "ReaderCore"),
        .executableTarget(
            name: "Leaf",
            dependencies: ["ReaderCore"],
            resources: [.copy("Resources/LocalKokoro.py"), .copy("Resources/LocalKokoro.requirements.txt")],
            linkerSettings: [.linkedFramework("CoreServices")]
        ),
        .testTarget(name: "ReaderCoreTests", dependencies: ["ReaderCore"]),
        .testTarget(name: "LeafTests", dependencies: ["Leaf", "ReaderCore"])
    ]
)
