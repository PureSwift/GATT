// swift-tools-version: 6.2
import PackageDescription

// A `CentralManager` conformer built in Embedded Swift, so CI checks that the
// protocol and its streams specialize with a concrete `Failure`. Embedded Swift
// compiles generic code only where it is used, so building the `GATT` target
// alone can't catch that.
let package = Package(
    name: "EmbeddedCentral",
    dependencies: [
        .package(name: "GATT", path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "EmbeddedCentral",
            dependencies: [
                .product(name: "GATT", package: "GATT")
            ],
            linkerSettings: [
                // String comparison in Embedded Swift needs the Unicode tables.
                .linkedLibrary("swiftUnicodeDataTables")
            ]
        )
    ]
)
