//
//  CentralManagerTests.swift
//  GATT
//

import XCTest
import Bluetooth
@testable import GATT

/// `CentralManager`'s typed `Failure`, its streams, and the single-threaded
/// stream Embedded builds use.
final class CentralManagerTests: XCTestCase {

    // MARK: Typed and untyped conformers

    func testUntypedConformerInfersAnyError() {
        XCTAssertTrue(UntypedCentral.Failure.self == (any Error).self)
        XCTAssertTrue(AsyncCentralScan<UntypedCentral>.Failure.self == (any Error).self)
        XCTAssertTrue(AsyncCentralNotifications<UntypedCentral>.Failure.self == (any Error).self)
    }

    func testTypedConformerThrowsItsFailure() async {
        let central = TypedCentral()
        do {
            try await central.connect(to: .init(id: 1))
            XCTFail("connect should throw")
        } catch {
            // `error` is TestError: this only compiles because the call is typed.
            XCTAssertEqual(error, .disconnected)
        }
    }

    func testTypedScanDeliversResultsThenItsFailure() async throws {
        let central = TypedCentral()
        central.scanResults = [1, 2]
        central.scanFailure = .scanFailed
        let scan = try await central.scan(filterDuplicates: true)
        var iterator = scan.makeAsyncIterator()
        let first = try await iterator.next()
        let second = try await iterator.next()
        XCTAssertEqual(first?.peripheral.id, 1)
        XCTAssertEqual(second?.peripheral.id, 2)
        do {
            _ = try await iterator.next()
            XCTFail("the scan should end with its failure")
        } catch {
            XCTAssertEqual(error, .scanFailed)
        }
    }

    func testFirstStopsTheScan() async throws {
        let central = TypedCentral()
        central.scanResults = [7]
        let first = try await central.scan(filterDuplicates: true).first()
        XCTAssertEqual(first?.peripheral.id, 7)
        // Stopped by `first()`. The hosted stream may run `onTermination` again
        // when it's released (AsyncIndefiniteStream), so this is at least one.
        XCTAssertGreaterThanOrEqual(central.scanTerminations, 1)
    }

    func testTypedNotifications() async throws {
        let central = TypedCentral()
        let characteristic = Characteristic(id: 1, uuid: .bit16(0x2A19), peripheral: TypedCentral.Peripheral(id: 1), properties: [.notify])
        let notifications = try await central.notify(for: characteristic)
        var iterator = notifications.makeAsyncIterator()
        let first = try await iterator.next()
        let second = try await iterator.next()
        XCTAssertEqual(first, [1])
        XCTAssertEqual(second, [2])
        do {
            _ = try await iterator.next()
            XCTFail("notifications should end with their failure")
        } catch {
            XCTAssertEqual(error, .disconnected)
        }
    }

    // MARK: Single-threaded stream (Embedded builds)

    typealias Stream = AsyncCentralStream<Int, TestError>

    func testStreamDeliversBufferedElementsBeforeItsError() async {
        let stream = Stream(onTermination: { }) { continuation in
            continuation.yield(1)
            continuation.yield(2)
            continuation.finish(throwing: .scanFailed)
            continuation.yield(3) // ignored after finishing
        }
        let iterator = stream.makeAsyncIterator()
        let first = try? await iterator.next()
        let second = try? await iterator.next()
        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 2)
        do {
            _ = try await iterator.next()
            XCTFail("the stream should end with its error")
        } catch {
            XCTAssertEqual(error, .scanFailed)
        }
        // the error is thrown once; after it the stream just ends
        do {
            let afterError = try await iterator.next()
            XCTAssertNil(afterError)
        } catch {
            XCTFail("the error should be thrown only once, got \(error) again")
        }
        XCTAssertFalse(stream.isExecuting)
    }

    func testStreamKeepsTheNewestElements() async {
        let stream = Stream(bufferSize: 2, onTermination: { }) { continuation in
            for value in 1 ... 5 { continuation.yield(value) }
            continuation.finish()
        }
        let iterator = stream.makeAsyncIterator()
        var values = [Int]()
        while let value = try? await iterator.next() { values.append(value) }
        XCTAssertEqual(values, [4, 5])
    }

    @MainActor
    func testStreamResumesAWaitingIterator() async throws {
        var continuation: AsyncCentralContinuation<Int, TestError>!
        let stream = Stream(onTermination: { }) { continuation = $0 }
        let task = Task { @MainActor in
            var values = [Int]()
            let iterator = stream.makeAsyncIterator()
            while let value = try await iterator.next() { values.append(value) }
            return values
        }
        await Task.yield()
        continuation.yield(10)
        await Task.yield()
        continuation.yield(11)
        continuation.finish()
        let values = try await task.value
        XCTAssertEqual(values, [10, 11])
    }

    func testStreamRunsOnTerminationOnceWhenStopped() {
        var terminations = 0
        let stream = Stream(onTermination: { terminations += 1 }) { _ in }
        XCTAssertTrue(stream.isExecuting)
        stream.stop()
        stream.stop()
        XCTAssertEqual(terminations, 1)
        XCTAssertFalse(stream.isExecuting)
    }

    func testStreamRunsOnTerminationWhenReleased() {
        var terminations = 0
        do {
            let stream = Stream(onTermination: { terminations += 1 }) { $0.yield(1) }
            _ = stream.isExecuting
        }
        XCTAssertEqual(terminations, 1)
    }

    @MainActor
    func testCancellingAWaitingIteratorEndsTheStream() async throws {
        var terminations = 0
        let stream = Stream(onTermination: { terminations += 1 }) { _ in }
        let task = Task { @MainActor in
            try await stream.makeAsyncIterator().next()
        }
        await Task.yield()
        task.cancel()
        let value = try await task.value
        XCTAssertNil(value)
        XCTAssertEqual(terminations, 1)
        XCTAssertFalse(stream.isExecuting)
    }

    @MainActor
    func testCancellingBeforeWaitingEndsTheStream() async throws {
        var terminations = 0
        let stream = Stream(onTermination: { terminations += 1 }) { _ in }
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await stream.makeAsyncIterator().next()
        }
        let value = try await task.value
        XCTAssertNil(value)
        XCTAssertEqual(terminations, 1)
    }
}

// MARK: - Test centrals

enum TestError: Error, Equatable {
    case disconnected
    case scanFailed
    case notSupported
}

struct TestPeer: Peer {
    let id: Int
}

struct TestAdvertisement: AdvertisementData {
    typealias Data = [UInt8]
    var localName: String? { nil }
    var manufacturerData: ManufacturerSpecificData<[UInt8]>? { nil }
    var txPowerLevel: Double? { nil }
    var serviceData: [BluetoothUUID: [UInt8]]? { nil }
    var serviceUUIDs: [BluetoothUUID]? { nil }
    var solicitedServiceUUIDs: [BluetoothUUID]? { nil }
}

/// A conformer with a typed failure, on the hosted stream.
final class TypedCentral: CentralManager, @unchecked Sendable {

    typealias Failure = TestError
    typealias Peripheral = TestPeer
    typealias Advertisement = TestAdvertisement
    typealias AttributeID = Int
    typealias Data = [UInt8]

    var log: (@Sendable (String) -> ())?

    var scanResults = [Int]()
    var scanFailure: TestError?
    var scanTerminations = 0

    var peripherals: [TestPeer: Bool] { get async { [:] } }

    func scan(filterDuplicates: Bool) async throws(TestError) -> AsyncCentralScan<TypedCentral> {
        AsyncCentralScan(onTermination: { self.scanTerminations += 1 }) { continuation in
            for id in scanResults {
                continuation.yield(ScanData(peripheral: TestPeer(id: id), date: Date(), rssi: -50, advertisementData: TestAdvertisement(), isConnectable: true))
            }
            if let scanFailure {
                continuation.finish(throwing: scanFailure)
            }
        }
    }

    func connect(to peripheral: TestPeer) async throws(TestError) { throw .disconnected }
    func disconnect(_ peripheral: TestPeer) async { }
    func disconnectAll() async { }
    func discoverServices(_ services: Set<BluetoothUUID>, for peripheral: TestPeer) async throws(TestError) -> [Service<TestPeer, Int>] { [] }
    func discoverCharacteristics(_ characteristics: Set<BluetoothUUID>, for service: Service<TestPeer, Int>) async throws(TestError) -> [Characteristic<TestPeer, Int>] { [] }
    func readValue(for characteristic: Characteristic<TestPeer, Int>) async throws(TestError) -> [UInt8] { throw .notSupported }
    func writeValue(_ data: [UInt8], for characteristic: Characteristic<TestPeer, Int>, withResponse: Bool) async throws(TestError) { throw .notSupported }
    func discoverDescriptors(for characteristic: Characteristic<TestPeer, Int>) async throws(TestError) -> [Descriptor<TestPeer, Int>] { [] }
    func readValue(for descriptor: Descriptor<TestPeer, Int>) async throws(TestError) -> [UInt8] { throw .notSupported }
    func writeValue(_ data: [UInt8], for descriptor: Descriptor<TestPeer, Int>) async throws(TestError) { throw .notSupported }

    func notify(for characteristic: Characteristic<TestPeer, Int>) async throws(TestError) -> AsyncCentralNotifications<TypedCentral> {
        AsyncCentralNotifications(onTermination: { }) { continuation in
            continuation.yield([1])
            continuation.yield([2])
            continuation.finish(throwing: TestError.disconnected)
        }
    }

    func maximumTransmissionUnit(for peripheral: TestPeer) async throws(TestError) -> MaximumTransmissionUnit { .default }
    func rssi(for peripheral: TestPeer) async throws(TestError) -> RSSI { throw .notSupported }
}

/// A conformer written before `Failure` existed: untyped `throws` everywhere,
/// and the closure-based stream initializer.
final class UntypedCentral: CentralManager, @unchecked Sendable {

    typealias Peripheral = TestPeer
    typealias Advertisement = TestAdvertisement
    typealias AttributeID = Int
    typealias Data = [UInt8]

    var log: (@Sendable (String) -> ())?

    var peripherals: [TestPeer: Bool] { get async { [:] } }

    func scan(filterDuplicates: Bool) async throws -> AsyncCentralScan<UntypedCentral> {
        AsyncCentralScan { _ in }
    }

    func connect(to peripheral: TestPeer) async throws { }
    func disconnect(_ peripheral: TestPeer) async { }
    func disconnectAll() async { }
    func discoverServices(_ services: Set<BluetoothUUID>, for peripheral: TestPeer) async throws -> [Service<TestPeer, Int>] { [] }
    func discoverCharacteristics(_ characteristics: Set<BluetoothUUID>, for service: Service<TestPeer, Int>) async throws -> [Characteristic<TestPeer, Int>] { [] }
    func readValue(for characteristic: Characteristic<TestPeer, Int>) async throws -> [UInt8] { [] }
    func writeValue(_ data: [UInt8], for characteristic: Characteristic<TestPeer, Int>, withResponse: Bool) async throws { }
    func discoverDescriptors(for characteristic: Characteristic<TestPeer, Int>) async throws -> [Descriptor<TestPeer, Int>] { [] }
    func readValue(for descriptor: Descriptor<TestPeer, Int>) async throws -> [UInt8] { [] }
    func writeValue(_ data: [UInt8], for descriptor: Descriptor<TestPeer, Int>) async throws { }
    func notify(for characteristic: Characteristic<TestPeer, Int>) async throws -> AsyncCentralNotifications<UntypedCentral> {
        AsyncCentralNotifications { _ in }
    }
    func maximumTransmissionUnit(for peripheral: TestPeer) async throws -> MaximumTransmissionUnit { .default }
    func rssi(for peripheral: TestPeer) async throws -> RSSI { RSSI(rawValue: -50)! }
}
