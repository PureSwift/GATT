// swift-tools-version:4.1
import PackageDescription

_ = Package(name: "GATT",
            products: [
                .library(
                    name: "GATT",
                    targets: ["GATT"]
                ),
                .library(
                    name: "DarwinGATT",
                    targets: ["DarwinGATT"]
                )
            ],
            dependencies: [
                .package(url: "https://github.com/PureSwift/Bluetooth.git", .branch("master"))
            ],
            targets: [
                .target(name: "GATT", dependencies: ["Bluetooth"]),
                .target(name: "DarwinGATT", dependencies: ["GATT"]),
                .testTarget(name: "GATTTests", dependencies: ["GATT"])
            ],
            swiftLanguageVersions: [4])
