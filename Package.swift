// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Voxly",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Voxly", targets: ["VoxlyApp"])],
    targets: [.executableTarget(name: "VoxlyApp")]
)
