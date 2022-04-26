# GATT

[![Swift][swift-badge]][swift-url]
[![Platform][platform-badge]][platform-url]
[![Release][release-badge]][release-url]
[![License][mit-badge]][mit-url]

Bluetooth Generic Attribute Profile (GATT) for Swift

## Usage

### Peripheral

```swift
import Bluetooth
#if canImport(Darwin)
import DarwinGATT
#elseif os(Linux)
import BluetoothLinux
#endif

#if os(Linux)
typealias LinuxPeripheral = GATTPeripheral<BluetoothLinux.HostController, BluetoothLinux.L2CAPSocket>
guard let hostController = await HostController.default else {
    fatalError("No Bluetooth hardware connected")
}
let serverOptions = GATTPeripheralOptions(
    maximumTransmissionUnit: .max,
    maximumPreparedWrites: 1000
)
let peripheral = LinuxPeripheral(
    hostController: hostController,
    options: serverOptions,
    socket: BluetoothLinux.L2CAPSocket.self
)
#elseif canImport(Darwin)
let peripheral = DarwinPeripheral()
#else
#error("Unsupported platform")
#endif

// start advertising
try await peripheral.start()

```

### Central

```swift
import Bluetooth
#if canImport(Darwin)
import DarwinGATT
#elseif os(Linux)
import BluetoothLinux
#endif

#if os(Linux)
typealias LinuxCentral = GATTCentral<BluetoothLinux.HostController, BluetoothLinux.L2CAPSocket>
let hostController = await HostController.default
let central = LinuxCentral(
    hostController: hostController,
    socket: BluetoothLinux.L2CAPSocket.self
)
#elseif canImport(Darwin)
let central = DarwinCentral()
#else
#error("Unsupported platform")
#endif

// start scanning
let stream = try await central.scan(filterDuplicates: true)
for try await scanData in stream {
    print(scanData)
    stream.stop()
}

```

## Documentation

Read the documentation [here](http://pureswift.github.io/GATT/documentation/gatt/).
Documentation can be generated with [DocC](https://github.com/apple/swift-docc).

## See Also

- [Bluetooth](https://github.com/PureSwift/Bluetooth) - Pure Swift Bluetooth Definitions
- [BluetoothLinux](https://github.com/PureSwift/BluetoothLinux) - Pure Swift Linux Bluetooth Stack
- [Netlink](https://github.com/PureSwift/Netlink) - Swift library for communicating with Linux Kernel Netlink subsystem (Linux Only) 

License
-------

**GATT** is released under the MIT license. See LICENSE for details.

[swift-badge]: https://img.shields.io/badge/swift-5.6-F05138.svg "Swift 5.6"
[swift-url]: https://swift.org
[platform-badge]: https://img.shields.io/badge/platform-macOS%20%7C%20iOS%20%7C%20watchOS%20%7C%20tvOS%20%7C%20Linux%20%7C%20Android-lightgrey.svg
[platform-url]: https://swift.org
[mit-badge]: https://img.shields.io/badge/License-MIT-blue.svg?style=flat
[mit-url]: https://tldrlegal.com/license/mit-license
[build-status-badge]: https://github.com/PureSwift/GATT/workflows/Swift/badge.svg
[build-status-url]: https://github.com/PureSwift/GATT/actions
[release-badge]: https://img.shields.io/github/release/PureSwift/GATT.svg
[release-url]: https://github.com/PureSwift/GATT/releases
[docs-url]: http://pureswift.github.io/GATT/documentation/GATT/
