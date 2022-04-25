// swift-tools-version:5.5
import PackageDescription

let libraryType: PackageDescription.Product.Library.LibraryType = .static

let package = Package(
    name: "GATT",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .watchOS(.v6),
        .tvOS(.v13),
    ],
    products: [
        .library(
            name: "GATT",
            type: libraryType,
            targets: ["GATT"]
        ),
        .library(
            name: "DarwinGATT",
            targets: ["DarwinGATT"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/PureSwift/Bluetooth.git",
            .branch("master")
        ),
        .package(
            url: "https://github.com/apple/swift-docc-plugin.git", 
            from: "1.0.0"
        )
    ],
    targets: [
        .target(
            name: "GATT",
            dependencies: [
                .product(
                    name: "Bluetooth",
                    package: "Bluetooth"
                ),
                .product(
                    name: "BluetoothGATT",
                    package: "Bluetooth",
                    condition: .when(platforms: [.macOS, .linux])
                ),
                .product(
                    name: "BluetoothGAP",
                    package: "Bluetooth",
                    condition: .when(platforms: [.macOS, .linux])
                ),
                .product(
                    name: "BluetoothHCI",
                    package: "Bluetooth",
                    condition: .when(platforms: [.macOS, .linux])
                ),
            ]
        ),
        .target(
            name: "DarwinGATT",
            dependencies: [
                "GATT",
                .product(
                    name: "BluetoothGATT",
                    package: "Bluetooth",
                    condition: .when(platforms: [.macOS])
                )
            ]
        ),
        .testTarget(
            name: "GATTTests",
            dependencies: [
                "GATT",
                .product(
                    name: "Bluetooth",
                    package: "Bluetooth"
                ),
                .product(
                    name: "BluetoothGATT",
                    package: "Bluetooth"
                ),
                .product(
                    name: "BluetoothGAP",
                    package: "Bluetooth"
                ),
                .product(
                    name: "BluetoothHCI",
                    package: "Bluetooth"
                )
            ]
        )
    ]
)
