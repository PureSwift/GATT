import PackageDescription

let package = Package(
    name: "GATT",
    dependencies: [
        .Package(url: "https://github.com/PureSwift/BluetoothLinux.git", majorVersion: 1)
    ],
    targets: [
        Target(
            name: "UnitTests",
            dependencies: [.Target(name: "GATT")]),
        Target(
            name: "GATT")
    ]
)