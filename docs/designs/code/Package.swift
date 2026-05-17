// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DesignPreviewKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "DesignPreviewKit", targets: ["DesignPreviewKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
    ],
    targets: [
        .target(
            name: "DesignPreviewKit",
            path: "Sources/DesignPreviewKit"
        ),
        .testTarget(
            name: "DesignPreviewSnapshotTests",
            dependencies: [
                "DesignPreviewKit",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            path: "Tests/DesignPreviewSnapshotTests",
            exclude: ["__Snapshots__"],
            resources: []
        ),
    ]
)
