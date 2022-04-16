// swift-tools-version:5.1
import PackageDescription

let libraryType: PackageDescription.Product.Library.LibraryType = .static

let package = Package(
    name: "GATT",
    products: [
        .library(
            name: "GATT",
            type: libraryType,
            targets: ["GATT"]
        ),
        .library(
            name: "DarwinGATT",
            type: libraryType,
            targets: ["DarwinGATT"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/PureSwift/Bluetooth.git",
            .branch("master")
        )
    ],
    targets: [
        .target(
            name: "GATT",
            dependencies: [
                "Bluetooth"
            ]
        ),
        .target(
            name: "DarwinGATT",
            dependencies: [
                "GATT"
            ]
        ),
        .testTarget(
            name: "GATTTests",
            dependencies: [
                "GATT",
                "Bluetooth"
            ]
        )
    ]
)
