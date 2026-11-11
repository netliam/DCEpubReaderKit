// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DCEpubReaderKit",
    platforms: [.iOS(.v16)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "DCEpubReaderKit",
            targets: ["DCEpubReaderKit"]
        )
    ],
    targets: [
        .target(
            name: "DCEpubCore"
        ),
        .target(
            name: "DCEpubParser",
            dependencies: ["DCEpubCore"]
        ),
        .target(
            name: "DCEpubRendering",
            dependencies: ["DCEpubCore"],
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "DCEpubReaderKit",
            dependencies: [
                "DCEpubCore",
                "DCEpubParser",
                "DCEpubRendering"
            ]
        ),
        .testTarget(
            name: "DCEpubReaderKitTests",
            dependencies: [
                "DCEpubCore",
                "DCEpubParser",
                "DCEpubRendering"
            ],
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
