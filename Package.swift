import PackageDescription

let package = Package(
    name: "GATT",
    targets: [
        Target(name: "GATT"),
        Target(
          name: "DarwinGATT",
          dependencies: [.Target(name: "GATT")]
        )
    ],
    dependencies: [
        .Package(url: "https://github.com/PureSwift/BluetoothLinux.git", majorVersion: 3),
        .Package(url: "git@github.com:PureSwift/Android.git", majorVersion: 0)
    ],
    exclude: ["Xcode", "Carthage"]
)
