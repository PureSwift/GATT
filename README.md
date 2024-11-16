# GATT

[![Swift][swift-badge]][swift-url]
[![Platform][platform-badge]][platform-url]
[![Release][release-badge]][release-url]
[![License][mit-badge]][mit-url]

Bluetooth Generic Attribute Profile (GATT) for Swift

## Installation 

GATT is available as a Swift Package Manager package. To use it, add the following dependency in your `Package.swift`:

```swift
.package(url: "https://github.com/PureSwift/GATT.git", branch: "master"),
```

and to your target, add `GATT` to your dependencies. You can then `import GATT` to get access to GATT functionality.

## Platforms

| Platform | Roles | Backend | Library |
| ---- | -------- | --- | ----------- | 
| macOS, iOS, watchOS, tvOS, visionOS | Central, Peripheral | [CoreBluetooth](https://developer.apple.com/documentation/corebluetooth) | [DarwinGATT](https://github.com/PureSwift/GATT) |
| Linux | Central, Peripheral | [BlueZ](https://www.bluez.org) | [BluetoothLinux](https://github.com/PureSwift/BluetoothLinux), [GATT](https://github.com/PureSwift/GATT)
| Android | Central | [Java Native Interface](https://developer.android.com/training/articles/perf-jni) | [AndroidBluetooth](https://github.com/PureSwift/AndroidBluetooth)
| WebAssembly | Central | [Bluetooth Web API](https://developer.mozilla.org/en-US/docs/Web/API/Web_Bluetooth_API) | [BluetoothWeb](https://github.com/PureSwift/BluetoothWeb)
| Pi Pico W | Peripheral | [BlueKitchen BTStack](https://bluekitchen-gmbh.com/btstack/#quick_start/index.html) | [BTStack](https://github.com/MillerTechnologyPeru/BTStack)
| ESP32 | Peripheral | [Apache NimBLE](https://mynewt.apache.org/latest/network/index.html) | [NimBLE](https://github.com/MillerTechnologyPeru/NimBLE)
| nRF52840 | Peripheral | [Zephyr SDK](https://zephyrproject.org) | [Zephyr](https://github.com/MillerTechnologyPeru/Zephyr-Swift)

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

License
-------

**GATT** is released under the MIT license. See LICENSE for details.

[swift-badge]: https://img.shields.io/badge/swift-6.0-F05138.svg "Swift 6.0"
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
