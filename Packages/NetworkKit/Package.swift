// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NetworkKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "NetworkKit", targets: ["NetworkKit"])
    ],
    targets: [
        // Vendored single-file Zstandard decompressor (facebook/zstd, BSD).
        // Needed for mihomo .mrs rule-sets, which are zstd-compressed and which
        // Apple's Compression framework cannot decode.
        .target(
            name: "CZstd"
        ),
        .target(
            name: "NetworkKit",
            dependencies: ["CZstd"],
            resources: [
                .copy("HappKeys")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "NetworkKitTests",
            dependencies: ["NetworkKit"]
        )
    ]
)
