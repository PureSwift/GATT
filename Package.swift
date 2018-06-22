import PackageDescription

let package = Package(
    name: "GATT",
    targets: [
        Target(name: "GATT")
    ],
    dependencies: [
        .Package(url: "https://github.com/PureSwift/BluetoothLinux.git", majorVersion: 3)
    ],
    exclude: ["Xcode", "Carthage"]
)
