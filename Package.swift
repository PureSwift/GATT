import PackageDescription

let package = Package(
    name: "GATT",
    targets: [
        Target(
            name: "GATTTest",
            dependencies: [.Target(name: "GATT")]),
        Target(
            name: "PeripheralUnitTestsServer",
            dependencies: [
                .Target(name: "GATT"),
                .Target(name: "GATTTest")
            ]),
        Target(
            name: "PeripheralUnitTestsClient",
            dependencies: [
                .Target(name: "GATT"),
                .Target(name: "GATTTest")
            ]),
        Target(
            name: "GATT")
    ],
    dependencies: [
        .Package(url: "https://github.com/PureSwift/BluetoothLinux.git", majorVersion: 3)
    ],
    exclude: ["Xcode", "Carthage"]
)
