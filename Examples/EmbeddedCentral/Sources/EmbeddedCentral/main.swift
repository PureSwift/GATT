#if hasFeature(Embedded)
import _Concurrency
#endif
import Bluetooth
import GATT

/// The mock's typed failure. (In an Embedded debug build, GATT's own
/// `CentralError` can't be used here yet: its `Error` witness table isn't
/// emitted by the GATT module, and the link fails.)
enum MockError: Error {
    case disconnected
    case invalidAttribute(BluetoothUUID)
}

/// A central with no radio: it reports one peripheral and a value, and
/// fails everything else with a typed error.
final class MockCentral: CentralManager {

    typealias Failure = MockError

    struct Peripheral: Peer {
        let id: UInt64
    }

    struct Advertisement: AdvertisementData {
        typealias Data = [UInt8]
        var localName: String? { "Embedded" }
        var manufacturerData: ManufacturerSpecificData<[UInt8]>? { nil }
        var txPowerLevel: Double? { nil }
        var serviceData: [BluetoothUUID: [UInt8]]? { nil }
        var serviceUUIDs: [BluetoothUUID]? { nil }
        var solicitedServiceUUIDs: [BluetoothUUID]? { nil }
    }

    typealias AttributeID = UInt16
    typealias Data = [UInt8]

    var log: (@Sendable (String) -> ())?

    var stoppedScanning = false

    var peripherals: [Peripheral: Bool] {
        get async { [Peripheral(id: 1): false] }
    }

    func scan(filterDuplicates: Bool) async throws(MockError) -> AsyncCentralScan<MockCentral> {
        AsyncCentralScan(onTermination: { self.stoppedScanning = true }) { continuation in
            continuation.yield(ScanData(
                peripheral: Peripheral(id: 1),
                date: 0,
                rssi: -50,
                advertisementData: Advertisement(),
                isConnectable: true
            ))
        }
    }

    func connect(to peripheral: Peripheral) async throws(MockError) {
        throw .disconnected
    }

    func disconnect(_ peripheral: Peripheral) async { }

    func disconnectAll() async { }

    func discoverServices(_ services: Set<BluetoothUUID>, for peripheral: Peripheral) async throws(MockError) -> [Service<Peripheral, UInt16>] {
        [Service(id: 1, uuid: .bit16(0x180F), peripheral: peripheral)]
    }

    func discoverCharacteristics(_ characteristics: Set<BluetoothUUID>, for service: Service<Peripheral, UInt16>) async throws(MockError) -> [Characteristic<Peripheral, UInt16>] {
        [Characteristic(id: 2, uuid: .bit16(0x2A19), peripheral: service.peripheral, properties: [.read, .notify])]
    }

    func readValue(for characteristic: Characteristic<Peripheral, UInt16>) async throws(MockError) -> [UInt8] {
        [100]
    }

    func writeValue(_ data: [UInt8], for characteristic: Characteristic<Peripheral, UInt16>, withResponse: Bool) async throws(MockError) {
        throw .invalidAttribute(characteristic.uuid)
    }

    func discoverDescriptors(for characteristic: Characteristic<Peripheral, UInt16>) async throws(MockError) -> [Descriptor<Peripheral, UInt16>] {
        []
    }

    func readValue(for descriptor: Descriptor<Peripheral, UInt16>) async throws(MockError) -> [UInt8] {
        throw .invalidAttribute(descriptor.uuid)
    }

    func writeValue(_ data: [UInt8], for descriptor: Descriptor<Peripheral, UInt16>) async throws(MockError) {
        throw .invalidAttribute(descriptor.uuid)
    }

    func notify(for characteristic: Characteristic<Peripheral, UInt16>) async throws(MockError) -> AsyncCentralNotifications<MockCentral> {
        AsyncCentralNotifications(onTermination: { }) { continuation in
            continuation.yield([99])
            continuation.yield([98])
            continuation.finish(throwing: .disconnected)
        }
    }

    func maximumTransmissionUnit(for peripheral: Peripheral) async throws(MockError) -> MaximumTransmissionUnit {
        .default
    }

    func rssi(for peripheral: Peripheral) async throws(MockError) -> RSSI {
        throw .disconnected
    }
}

/// Generic code over the protocol, as an app's model would be written.
func firstValue<Central: CentralManager>(_ central: Central) async throws(Central.Failure) -> Central.Data? {
    guard let scan = try await central.scan(filterDuplicates: true).first() else { return nil }
    let service = try await central.discoverServices([], for: scan.peripheral)[0]
    let characteristic = try await central.discoverCharacteristics([], for: service)[0]
    return try await central.readValue(for: characteristic)
}

func check(_ condition: Bool, _ message: StaticString) -> Bool {
    if !condition { print(message) }
    return condition
}

func run() async -> Bool {
    let central = MockCentral()
    var passed = true
    do {
        let value = try await firstValue(central)
        passed = check(value == [100], "read the wrong value") && passed
        passed = check(central.stoppedScanning, "first() didn't stop the scan") && passed
        let characteristic = Characteristic<MockCentral.Peripheral, UInt16>(
            id: 2, uuid: .bit16(0x2A19), peripheral: .init(id: 1), properties: [.notify])
        var values = [[UInt8]]()
        do {
            for try await value in try await central.notify(for: characteristic) {
                values.append(value)
            }
            passed = check(false, "notifications finished without their error") && passed
        } catch {
            // `error` is MockError here, not `any Error`.
            if case .disconnected = error { } else { passed = check(false, "wrong notification error") && passed }
        }
        passed = check(values == [[99], [98]], "wrong notification values") && passed
        do {
            try await central.connect(to: .init(id: 1))
            passed = check(false, "connect didn't throw") && passed
        } catch {
            if case .disconnected = error { } else { passed = check(false, "wrong connect error") && passed }
        }
    } catch {
        passed = check(false, "a call threw unexpectedly") && passed
    }
    return passed
}

let passed = await run()
print(passed ? "EmbeddedCentral: all checks passed" : "EmbeddedCentral: FAILED")
