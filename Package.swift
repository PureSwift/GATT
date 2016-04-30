import PackageDescription

let package = Package(
    name: "GATT",
    dependencies: [
        .Package(url: "https://github.com/PureSwift/BluetoothLinux.git", majorVersion: 2)
    ],
    targets: [
        Target(
            name: "GATTTest",
            dependencies: [.Target(name: "GATT")]),
        Target(
            name: "PeripheralUnitTestsServer",
            dependencies: [.Target(name: "GATT"), .Target(name: "GATTTest")]),
        Target(
            name: "GATT")
    ],
    exclude: ["Xcode", "Sources/PeripheralUnitTestsClient", "Sources/GATT/DarwinCentral.swift", "Sources/GATT/DarwinPeripheral.swift"]
)