// swift-tools-version:5.0
import PackageDescription

_ = Package(name: "GATT",
            products: [
                .library(
                    name: "GATT",
                    type: .dynamic,
                    targets: ["GATT"]
                ),
                .library(
                    name: "DarwinGATT",
                    type: .dynamic,
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
                .target(name: "GATT", dependencies: ["Bluetooth"]),
                .target(name: "DarwinGATT", dependencies: ["GATT"]),
                .testTarget(name: "GATTTests", dependencies: ["GATT"])
            ],
            swiftLanguageVersions: [.v5])
