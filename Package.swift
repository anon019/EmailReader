// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EmailReader",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "EmailReader", targets: ["EmailReaderApp"]),
        .executable(name: "EmailReaderWorker", targets: ["EmailReaderWorker"]),
        .executable(name: "EmailReaderSmokeTests", targets: ["EmailReaderSmokeTests"])
    ],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "EmailReaderCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "EmailReaderApp", dependencies: ["EmailReaderCore"]),
        .executableTarget(name: "EmailReaderWorker", dependencies: ["EmailReaderCore"]),
        .executableTarget(name: "EmailReaderSmokeTests", dependencies: ["EmailReaderCore"])
    ]
)
