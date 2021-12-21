//
//  DarwinCentral.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/3/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//
#if swift(>=5.5) && canImport(CoreBluetooth)
import Foundation
import Dispatch
import CoreBluetooth
import Bluetooth
import GATT

@available(macOS 10.5, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public final class DarwinCentral: CentralManager {
    
    // MARK: - Properties
    
    public let options: Options
    
    public let state: AsyncStream<DarwinBluetoothState>
    
    public let log: AsyncStream<String>
    
    public let isScanning: AsyncStream<Bool>
    
    public let didDisconnect: AsyncStream<Peripheral>
    
    /// Currently scanned devices, or restored devices.
    public var peripherals: Set<Peripheral> {
        get async {
            return await withUnsafeContinuation { [weak self] continuation in
                guard let self = self else { return }
                self.async {
                    let peripherals = Set(self.cache.peripherals.keys)
                    continuation.resume(returning: peripherals)
                }
            }
        }
    }
    
    private var centralManager: CBCentralManager!
    
    private var delegate: Delegate!
    
    private let queue: DispatchQueue?
    
    fileprivate var cache = Cache()
    
    fileprivate var continuation: Continuation
    
    // MARK: - Initialization
    
    /// Initialize with the specified options.
    ///
    /// - Parameter options: An optional dictionary containing initialization options for a central manager.
    /// For available options, see [Central Manager Initialization Options](apple-reference-documentation://ts1667590).
    public init(
        options: Options = Options(),
        queue: DispatchQueue? = nil
    ) {
        var continuation = Continuation()
        self.log = AsyncStream(String.self, bufferingPolicy: .bufferingNewest(10)) {
            continuation.log = $0
        }
        self.isScanning = AsyncStream(Bool.self, bufferingPolicy: .bufferingNewest(1)) {
            continuation.isScanning = $0
        }
        self.didDisconnect = AsyncStream(Peripheral.self, bufferingPolicy: .bufferingNewest(1)) {
            continuation.didDisconnect = $0
        }
        self.state = AsyncStream(DarwinBluetoothState.self, bufferingPolicy: .bufferingNewest(1)) {
            continuation.state = $0
        }
        self.options = options
        self.continuation = continuation
        self.queue = queue
        self.delegate = options.restoreIdentifier == nil ? Delegate(self) : RestorableDelegate(self)
        self.centralManager = CBCentralManager(
            delegate: self.delegate,
            queue: self.queue,
            options: options.optionsDictionary
        )
    }
    
    // MARK: - Methods
    
    public func wait(for state: DarwinBluetoothState) async throws {
        
    }
    
    /// Scans for peripherals that are advertising services.
    public func scan(
        filterDuplicates: Bool = true
    ) -> AsyncThrowingStream<ScanData<Peripheral, Advertisement>, Error> {
        return scan(with: [], filterDuplicates: filterDuplicates)
    }
    
    /// Scans for peripherals that are advertising services.
    public func scan(
        with services: Set<BluetoothUUID>,
        filterDuplicates: Bool = true
    ) -> AsyncThrowingStream<ScanData<Peripheral, Advertisement>, Error> {
        let serviceUUIDs: [CBUUID]? = services.isEmpty ? nil : services.map { CBUUID($0) }
        let options: [String: Any] = [
            CBCentralManagerScanOptionAllowDuplicatesKey: NSNumber(value: filterDuplicates == false)
        ]
        self.log("Will scan for nearby devices")
        return AsyncThrowingStream(ScanData<Peripheral, Advertisement>.self, bufferingPolicy: .bufferingNewest(100)) {  [weak self] continuation in
            guard let self = self else { return }
            self.async {
                // cancel old scanning task
                if let oldContinuation = self.continuation.scan {
                    oldContinuation.finish(throwing: CancellationError())
                    self.continuation.scan = nil
                }
                // reset cache
                self.cache = Cache()
                // start scanning
                assert(self.continuation.scan == nil)
                self.continuation.scan = continuation
                self.continuation.isScanning.yield(true)
                self.centralManager.scanForPeripherals(withServices: serviceUUIDs, options: options)
            }
        }
    }
    
    public func stopScan() async {
        self.log("Stopped scanning")
        return await withCheckedContinuation { [weak self] continuation in
            guard let self = self else { return }
            self.async {
                guard let scanContinuation = self.continuation.scan else {
                    continuation.resume() // not currently scanning
                    return
                }
                self.centralManager.stopScan()
                self.continuation.isScanning.yield(false)
                self.log("Discovered \(self.cache.peripherals.count) peripherals")
                scanContinuation.finish(throwing: nil) // end stream
                continuation.resume()
                self.continuation.scan = nil
            }
        }
    }
    
    public func connect(
        to peripheral: Peripheral
    ) async throws {
        try await connect(to: peripheral, options: nil)
    }
    
    /// Connect to the specifed peripheral.
    /// - Parameter peripheral: The peripheral to which the central is attempting to connect.
    /// - Parameter options: A dictionary to customize the behavior of the connection.
    /// For available options, see [Peripheral Connection Options](apple-reference-documentation://ts1667676).
    public func connect(
        to peripheral: Peripheral,
        options: [String: Any]?
    ) async throws {
        self.log("Will connect to \(peripheral)")
        return try await withThrowingContinuation(for: peripheral) { [weak self] continuation in
            guard let self = self else { return }
            self.async {
                let operation = Operation.Connect(
                    peripheral: peripheral,
                    options: options,
                    continuation: continuation
                )
                self.enqueue(.connect(operation), for: peripheral)
            }
        }
    }
    
    public func disconnect(_ peripheral: Peripheral) {
        self.log("Will disconnect \(peripheral)")
        self.async { [weak self] in
            guard let self = self else { return }
            // get CoreBluetooth objects from cache
            guard let peripheralObject = self.cache.peripherals[peripheral] else {
                return
            }
            self.centralManager.cancelPeripheralConnection(peripheralObject)
        }
    }
    
    public func disconnectAll() {
        self.log("Will disconnect all")
        self.async { [weak self] in
            guard let self = self else { return }
            // get CoreBluetooth objects from cache
            for peripheralObject in self.cache.peripherals.values {
                self.centralManager.cancelPeripheralConnection(peripheralObject)
            }
        }
    }
    
    public func discoverServices(
        _ services: Set<BluetoothUUID> = [],
        for peripheral: Peripheral
    ) async throws -> [DarwinCentral.Service] {
        self.log("Will discover services for \(peripheral)")
        return try await withThrowingContinuation(for: peripheral) { [weak self] continuation in
            guard let self = self else { return }
            self.async {
                let operation = Operation.DiscoverServices(
                    peripheral: peripheral,
                    services: services,
                    continuation: continuation
                )
                self.enqueue(.discoverServices(operation), for: peripheral)
            }
        }
    }
    
    public func discoverIncludedServices(
        _ services: Set<BluetoothUUID> = [],
        for service: DarwinCentral.Service
    ) async throws -> [DarwinCentral.Service] {
        self.log("Peripheral \(service.peripheral) will discover included services of service \(service.uuid)")
        return try await withThrowingContinuation(for: service.peripheral) { [weak self] continuation in
            guard let self = self else { return }
            self.async {
                let operation = Operation.DiscoverIncludedServices(
                    service: service,
                    services: services,
                    continuation: continuation
                )
                self.enqueue(.discoverIncludedServices(operation), for: service.peripheral)
            }
        }
    }
    
    public func discoverCharacteristics(
        _ characteristics: Set<BluetoothUUID> = [],
        for service: DarwinCentral.Service
    ) async throws -> [DarwinCentral.Characteristic] {
        self.log("Peripheral \(service.peripheral) will discover characteristics of service \(service.uuid)")
        return try await withThrowingContinuation(for: service.peripheral) { [weak self] continuation in
            guard let self = self else { return }
            self.async {
                let operation = Operation.DiscoverCharacteristics(
                    service: service,
                    characteristics: characteristics,
                    continuation: continuation
                )
                self.enqueue(.discoverCharacteristics(operation), for: service.peripheral)
            }
        }
    }
    
    public func readValue(
        for characteristic: DarwinCentral.Characteristic
    ) async throws -> Data {
        self.log("Peripheral \(peripheral) will read characteristic \(characteristic.uuid)")
        return try await withThrowingContinuation(for: peripheral) { [weak self] continuation in
            guard let self = self else { return }
            self.async {
                
            }
        }
    }
    
    public func writeValue(
        _ data: Data,
        for characteristic: DarwinCentral.Characteristic,
        withResponse: Bool = true
    ) async throws {
        let semaphore = self.semaphore(for: characteristic.peripheral)
        await semaphore.wait()
        defer { semaphore.signal() }
        self.log("Peripheral \(characteristic.peripheral) will write characteristic \(characteristic.uuid)")
        if withResponse {
            try await write(data, type: .withResponse, for: characteristic)
        } else {
            try await waitUntilCanSendWriteWithoutResponse(for: characteristic.peripheral)
            try await write(data, type: .withoutResponse, for: characteristic)
        }
    }
    
    public func notify(
        for characteristic: DarwinCentral.Characteristic
    ) -> AsyncThrowingStream<Data, Error> {
        self.log("Peripheral \(characteristic.peripheral) will enable notifications for characteristic \(characteristic.uuid)")
        return AsyncThrowingStream(Data.self, bufferingPolicy: .bufferingNewest(100)) { [weak self] continuation in
            guard let self = self else { return }
            self.async {
                let peripheral = characteristic.peripheral
                // get peripheral
                guard let peripheralObject = self.cache.peripherals[peripheral] else {
                    continuation.finish(throwing: CentralError.unknownPeripheral)
                    return
                }
                // get characteristic
                guard let characteristicObject = self.cache.characteristics[characteristic] else {
                    continuation.finish(throwing: CentralError.invalidAttribute(characteristic.uuid))
                    return
                }
                // check power on
                let state = self.centralManager._state
                guard state == .poweredOn else {
                    continuation.finish(throwing: DarwinCentralError.invalidState(state))
                    return
                }
                // check connected
                guard peripheralObject.state == .connected else {
                    continuation.finish(throwing: CentralError.disconnected)
                    return
                }
                // notify
                assert(self.continuation.notificationStream[characteristic] == nil)
                self.continuation.notificationStream[characteristic] = continuation
                peripheralObject.setNotifyValue(true, for: characteristicObject)
            }
        }
    }
    
    public func stopNotifications(
        for characteristic: DarwinCentral.Characteristic
    ) async throws {
        let semaphore = self.semaphore(for: characteristic.peripheral)
        await semaphore.wait()
        defer { semaphore.signal() }
        let peripheral = characteristic.peripheral
        self.log("Peripheral \(peripheral) will disable notifications for characteristic \(characteristic.uuid)")
        return try await withThrowingContinuation(for: peripheral) { [weak self] continuation in
            guard let self = self else { return }
            self.async {
                // get peripheral
                guard let peripheralObject = self.cache.peripherals[peripheral] else {
                    continuation.resume(throwing: CentralError.unknownPeripheral)
                    return
                }
                // get characteristic
                guard let characteristicObject = self.cache.characteristics[characteristic] else {
                    continuation.resume(throwing: CentralError.invalidAttribute(characteristic.uuid))
                    return
                }
                // check power on
                let state = self.centralManager._state
                guard state == .poweredOn else {
                    continuation.resume(throwing: DarwinCentralError.invalidState(state))
                    return
                }
                // check connected
                guard peripheralObject.state == .connected else {
                    continuation.resume(throwing: CentralError.disconnected)
                    return
                }
                // cancel old task
                if let oldTask = self.continuation.stopNotification[characteristic] {
                    oldTask.resume(throwing: CancellationError())
                    self.continuation.stopNotification[characteristic] = nil
                }
                // notify
                self.continuation.stopNotification[characteristic] = continuation
                peripheralObject.setNotifyValue(false, for: characteristicObject)
            }
        }
    }
    
    public func maximumTransmissionUnit(for peripheral: Peripheral) async throws -> MaximumTransmissionUnit {
        self.log("Will read MTU for \(peripheral)")
        if queue == nil, Thread.isMainThread {
            return try _maximumTransmissionUnit(for: peripheral) // optimization
        } else {
            return try await withThrowingContinuation(for: peripheral) { [weak self] continuation in
                guard let self = self else { return }
                self.async {
                    do {
                        let mtu = try self._maximumTransmissionUnit(for: peripheral)
                        continuation.resume(returning: mtu)
                    }
                    catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    private func _maximumTransmissionUnit(for peripheral: Peripheral) throws -> MaximumTransmissionUnit {
        assert(queue != nil || Thread.isMainThread, "Should only run on main thread")
        // get peripheral
        guard let peripheralObject = self.cache.peripherals[peripheral] else {
            throw CentralError.unknownPeripheral
        }
        // get MTU
        let rawValue = peripheralObject.maximumWriteValueLength(for: .withoutResponse) + 3
        assert(peripheralObject.mtuLength.intValue == rawValue)
        guard let mtu = MaximumTransmissionUnit(rawValue: UInt16(rawValue)) else {
            assertionFailure("Invalid MTU \(rawValue)")
            return .default
        }
        return mtu
    }
    
    public func rssi(for peripheral: Peripheral) async throws -> RSSI {
        self.log("Will read RSSI for \(peripheral)")
        return try await withThrowingContinuation(for: peripheral) { [weak self] continuation in
            guard let self = self else { return }
            self.async {
                // get peripheral
                guard let peripheralObject = self.cache.peripherals[peripheral] else {
                    continuation.resume(throwing: CentralError.unknownPeripheral)
                    return
                }
                // check power on
                let state = self.centralManager._state
                guard state == .poweredOn else {
                    continuation.resume(throwing: DarwinCentralError.invalidState(state))
                    return
                }
                // check connected
                guard peripheralObject.state == .connected else {
                    continuation.resume(throwing: CentralError.disconnected)
                    return
                }
                // cancel old task
                if let oldTask = self.continuation.readRSSI[peripheral] {
                    oldTask.resume(throwing: CancellationError())
                    self.continuation.readRSSI[peripheral] = nil
                }
                // read value
                self.continuation.readRSSI[peripheral] = continuation
                peripheralObject.readRSSI()
            }
        }
    }
    
    // MARK - Private Methods
    
    private func log(_ message: String) {
        continuation.log.yield(message)
    }
    
    private func async(_ body: @escaping () -> ()) {
        let queue = self.queue ?? .main
        if self.queue == nil, Thread.isMainThread {
            // run on main thread directly
            body()
        } else {
            queue.async(execute: body)
        }
    }
    
    private func enqueue(_ operation: Operation, for peripheral: Peripheral) {
        let context = self.continuation.peripherals[peripheral] ?? PeripheralContinuationContext()
        context.queue.append(operation)
    }
    
    private func write(
        _ data: Data,
        type: CBCharacteristicWriteType,
        for characteristic: DarwinCentral.Characteristic
    ) async throws {
        return try await withThrowingContinuation(for: characteristic.peripheral) { [weak self] continuation in
            guard let self = self else { return }
            self.async {
                let peripheral = characteristic.peripheral
                // get peripheral
                guard let peripheralObject = self.cache.peripherals[peripheral] else {
                    continuation.resume(throwing: CentralError.unknownPeripheral)
                    return
                }
                // get characteristic
                guard let characteristicObject = self.cache.characteristics[characteristic] else {
                    continuation.resume(throwing: CentralError.invalidAttribute(characteristic.uuid))
                    return
                }
                // check power on
                let state = self.centralManager._state
                guard state == .poweredOn else {
                    continuation.resume(throwing: DarwinCentralError.invalidState(state))
                    return
                }
                // check connected
                guard peripheralObject.state == .connected else {
                    continuation.resume(throwing: CentralError.disconnected)
                    return
                }
                // store continuation for callback
                if type == .withResponse {
                    // calls `peripheral:didWriteValueForCharacteristic:error:` only
                    // if you specified the write type as `.withResponse`.
                    assert(self.continuation.peripherals[peripheral]?.pendingContinuation == nil)
                    self.continuation.writeCharacteristic[characteristic] = continuation
                }
                // write data
                peripheralObject.writeValue(data, for: characteristicObject, type: type)
            }
        }
    }
    
    private func canSendWriteWithoutResponse(
        for peripheral: Peripheral
    ) async throws -> Bool {
        return try await withThrowingContinuation(for: peripheral) { [weak self] continuation in
            guard let self = self else { return }
            self.async {
                // get peripheral
                guard let peripheralObject = self.cache.peripherals[peripheral] else {
                    continuation.resume(throwing: CentralError.unknownPeripheral)
                    return
                }
                // yield value
                continuation.resume(returning: peripheralObject.canSendWriteWithoutResponse)
            }
        }
    }
    
    private func waitUntilCanSendWriteWithoutResponse(
        for peripheral: Peripheral
    ) async throws {
        return try await withThrowingContinuation(for: peripheral) { [weak self] continuation in
            guard let self = self else { return }
            self.async {
                // get peripheral
                guard let peripheralObject = self.cache.peripherals[peripheral] else {
                    continuation.resume(throwing: CentralError.unknownPeripheral)
                    return
                }
                if peripheralObject.canSendWriteWithoutResponse {
                    continuation.resume()
                } else {
                    // wait until delegate is called
                    assert(self.continuation.peripherals[peripheral]?.pendingContinuation == nil)
                    self.continuation.peripherals[peripheral]?.pendingContinuation = .isReadyToWriteWithoutResponse(continuation)
                }
            }
        }
    }
}

// MARK: - Supporting Types

@available(macOS 10.5, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public extension DarwinCentral {
    
    typealias Advertisement = DarwinAdvertisementData
    
    typealias State = DarwinBluetoothState
    
    typealias AttributeID = ObjectIdentifier
    
    typealias Service = GATT.Service<DarwinCentral.Peripheral, DarwinCentral.AttributeID>
    
    typealias Characteristic = GATT.Characteristic<DarwinCentral.Peripheral, DarwinCentral.AttributeID>
    
    typealias Descriptor = GATT.Descriptor<DarwinCentral.Peripheral, DarwinCentral.AttributeID>
    
    /// Central Peer
    ///
    /// Represents a remote central device that has connected to an app implementing the peripheral role on a local device.
    struct Peripheral: Peer {
        
        public let id: UUID
        
        internal init(_ peripheral: CBPeripheral) {
            self.id = peripheral.gattIdentifier
        }
    }
    
    /**
     Darwin GATT Central Options
     */
    struct Options {
        
        /**
         A Boolean value that specifies whether the system should display a warning dialog to the user if Bluetooth is powered off when the peripheral manager is instantiated.
         */
        public let showPowerAlert: Bool
        
        /**
         A string (an instance of NSString) containing a unique identifier (UID) for the peripheral manager that is being instantiated.
         The system uses this UID to identify a specific peripheral manager. As a result, the UID must remain the same for subsequent executions of the app in order for the peripheral manager to be successfully restored.
         */
        public let restoreIdentifier: String?
        
        /**
         Initialize options.
         */
        public init(showPowerAlert: Bool = false,
                    restoreIdentifier: String? = nil) {
            
            self.showPowerAlert = showPowerAlert
            self.restoreIdentifier = restoreIdentifier
        }
        
        internal var optionsDictionary: [String: Any] {
            var options = [String: Any](minimumCapacity: 2)
            if showPowerAlert {
                options[CBCentralManagerOptionShowPowerAlertKey] = showPowerAlert as NSNumber
            }
            options[CBCentralManagerOptionRestoreIdentifierKey] = restoreIdentifier
            return options
        }
    }
}

@available(macOS 10.5, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
internal extension DarwinCentral {
    
    struct Cache {
        var peripherals = [Peripheral: CBPeripheral]()
        var services = [DarwinCentral.Service: CBService]()
        var characteristics = [DarwinCentral.Characteristic: CBCharacteristic]()
        var descriptors = [DarwinCentral.Descriptor: CBCharacteristic]()
    }
    
    struct Continuation {
        
        var log: AsyncStream<String>.Continuation!
        var isScanning: AsyncStream<Bool>.Continuation!
        var didDisconnect: AsyncStream<Peripheral>.Continuation!
        var state: AsyncStream<DarwinBluetoothState>.Continuation!
        var scan: AsyncThrowingStream<ScanData<Peripheral, Advertisement>, Error>.Continuation?
        var peripherals = [Peripheral: PeripheralContinuationContext]()
    }
    
    final class PeripheralContinuationContext {
        var queue = [Operation]()
        var notificationStream = [AttributeID: AsyncThrowingStream<Data, Error>.Continuation]()
        var readRSSI: PeripheralContinuation<RSSI, Error>?
    }
}

@available(macOS 10.5, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
internal extension DarwinCentral {
    
    enum Operation {
        case connect(Connect)
        case discoverServices(DiscoverServices)
        case discoverIncludedServices(DiscoverIncludedServices)
        case discoverCharacteristics(DiscoverCharacteristics)
        case readCharacteristic(ReadCharacteristic)
        case writeCharacteristic(WriteCharacteristic)
        case discoverDescriptors(DiscoverDescriptors)
        case readDescriptor(ReadDescriptor)
        case writeDescriptor(WriteDescriptor)
        case isReadyToWriteWithoutResponse(WriteWithoutResponseReady)
        case setNotification(NotificationState)
    }
}

internal extension DarwinCentral.Operation {
    
    struct Connect {
        let peripheral: DarwinCentral.Peripheral
        let options: [String: Any]?
        let continuation: PeripheralContinuation<(), Error>
    }
    
    struct DiscoverServices {
        let peripheral: DarwinCentral.Peripheral
        let services: Set<BluetoothUUID>
        let continuation: PeripheralContinuation<[DarwinCentral.Service], Error>
    }
    
    struct DiscoverIncludedServices {
        let service: DarwinCentral.Service
        let services: Set<BluetoothUUID>
        let continuation: PeripheralContinuation<[DarwinCentral.Service], Error>
    }
    
    struct DiscoverCharacteristics {
        let service: DarwinCentral.Service
        let characteristics: Set<BluetoothUUID>
        let continuation: PeripheralContinuation<[DarwinCentral.Characteristic], Error>
    }
    
    struct ReadCharacteristic {
        let characteristic: DarwinCentral.Characteristic
        let continuation: PeripheralContinuation<Data, Error>
    }
    
    struct WriteCharacteristic {
        let characteristic: DarwinCentral.Characteristic
        let continuation: PeripheralContinuation<(), Error>
    }
    
    struct DiscoverDescriptors {
        let characteristic: DarwinCentral.Characteristic
        let continuation: PeripheralContinuation<[DarwinCentral.Descriptor], Error>
    }
    
    struct ReadDescriptor {
        let descriptor: DarwinCentral.Descriptor
        let continuation: PeripheralContinuation<Data, Error>
    }
    
    struct WriteDescriptor {
        let descriptor: DarwinCentral.Descriptor
        let continuation: PeripheralContinuation<(), Error>
    }
    
    struct WriteWithoutResponseReady {
        let characteristic: DarwinCentral.Characteristic
        let continuation: PeripheralContinuation<(), Error>
    }
    
    struct NotificationState {
        let characteristic: DarwinCentral.Characteristic
        let isEnabled: Bool
        let continuation: PeripheralContinuation<(), Error>
    }
}

@available(macOS 10.5, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
internal extension DarwinCentral {
    
    func execute(_ operation: DarwinCentral.Operation) {
        switch operation {
        case let .connect(operation):
            execute(operation)
        case let .discoverServices(operation):
            execute(operation)
        case let .discoverIncludedServices(operation):
            execute(operation)
        case let .discoverCharacteristics(operation):
            execute(operation)
        case let .readCharacteristic(operation):
            execute(operation)
        case let .writeCharacteristic(operation):
            execute(operation)
        case let .discoverDescriptors(operation):
            execute(operation)
        case let .readDescriptor(operation):
            execute(operation)
        case let .writeDescriptor(operation):
            execute(operation)
        case let .setNotification(operation):
            execute(operation)
        case let .isReadyToWriteWithoutResponse(operation):
            execute(operation)
        }
    }
    
    func execute(_ operation: Operation.Connect) {
        // check power on
        guard validateState(.poweredOn, for: operation.continuation) else {
            return
        }
        // get peripheral
        guard let peripheralObject = validatePeripheral(operation.peripheral, for: operation.continuation) else {
            return
        }
        // connect
        self.centralManager.connect(peripheralObject, options: operation.options)
    }
    
    func execute(_ operation: Operation.DiscoverServices) {
        // check power on
        guard validateState(.poweredOn, for: operation.continuation) else {
            return
        }
        // get peripheral
        guard let peripheralObject = validatePeripheral(operation.peripheral, for: operation.continuation) else {
            return
        }
        // check connected
        guard validateConnected(peripheralObject, for: operation.continuation) else {
            return
        }
        // discover
        let serviceUUIDs = operation.services.isEmpty ? nil : operation.services.map { CBUUID($0) }
        peripheralObject.discoverServices(serviceUUIDs)
    }
    
    func execute(_ operation: Operation.DiscoverIncludedServices) {
        // check power on
        guard validateState(.poweredOn, for: operation.continuation) else {
            return
        }
        // get peripheral
        guard let peripheralObject = validatePeripheral(operation.service.peripheral, for: operation.continuation) else {
            return
        }
        // check connected
        guard validateConnected(peripheralObject, for: operation.continuation) else {
            return
        }
        // get service
        guard let serviceObject = validateService(operation.service, for: operation.continuation) else {
            return
        }
        let serviceUUIDs = operation.services.isEmpty ? nil : operation.services.map { CBUUID($0) }
        peripheralObject.discoverIncludedServices(serviceUUIDs, for: serviceObject)
    }
    
    func execute(_ operation: Operation.DiscoverCharacteristics) {
        // check power on
        guard validateState(.poweredOn, for: operation.continuation) else {
            return
        }
        // get peripheral
        guard let peripheralObject = validatePeripheral(operation.service.peripheral, for: operation.continuation) else {
            return
        }
        // check connected
        guard validateConnected(peripheralObject, for: operation.continuation) else {
            return
        }
        // get service
        guard let serviceObject = validateService(operation.service, for: operation.continuation) else {
            return
        }
        // discover
        let characteristicUUIDs = operation.characteristics.isEmpty ? nil : operation.characteristics.map { CBUUID($0) }
        peripheralObject.discoverCharacteristics(characteristicUUIDs, for: serviceObject)
    }
    
    func execute(_ operation: Operation.ReadCharacteristic) {
        // check power on
        guard validateState(.poweredOn, for: operation.continuation) else {
            return
        }
        // get peripheral
        guard let peripheralObject = validatePeripheral(operation.characteristic.peripheral, for: operation.continuation) else {
            return
        }
        // check connected
        guard validateConnected(peripheralObject, for: operation.continuation) else {
            return
        }
        // get characteristic
        guard let characteristicObject = validateCharacteristic(operation.characteristic, for: operation.continuation) else {
            return
        }
        // read value
        peripheralObject.readValue(for: characteristicObject)
    }
    
    func execute(_ operation: Operation.WriteCharacteristic) {
        
    }
    
    func execute(_ operation: Operation.DiscoverDescriptors) {
        
    }
    
    func execute(_ operation: Operation.ReadDescriptor) {
        
    }
    
    func execute(_ operation: Operation.WriteDescriptor) {
        
    }
    
    func execute(_ operation: Operation.WriteWithoutResponseReady) {
        
    }
    
    func execute(_ operation: Operation.NotificationState) {
        
    }
}

private extension DarwinCentral {
    
    func validateState<T>(
        _ state: DarwinBluetoothState,
        for continuation: PeripheralContinuation<T, Error>
    ) -> Bool {
        let state = self.centralManager._state
        guard state == .poweredOn else {
            continuation.resume(throwing: DarwinCentralError.invalidState(state))
            return false
        }
        return true
    }
    
    func validatePeripheral<T>(
        _ peripheral: Peripheral,
        for continuation: PeripheralContinuation<T, Error>
    ) -> CBPeripheral? {
        // get peripheral
        guard let peripheralObject = self.cache.peripherals[peripheral] else {
            continuation.resume(throwing: CentralError.unknownPeripheral)
            return nil
        }
        assert(peripheralObject.delegate != nil)
        return peripheralObject
    }
    
    func validateConnected<T>(
        _ peripheral: CBPeripheral,
        for continuation: PeripheralContinuation<T, Error>
    ) -> Bool {
        guard peripheral.state == .connected else {
            continuation.resume(throwing: CentralError.disconnected)
            return false
        }
        return true
    }
    
    func validateService<T>(
        _ service: Service,
        for continuation: PeripheralContinuation<T, Error>
    ) -> CBService? {
        guard let serviceObject = self.cache.services[service] else {
            continuation.resume(throwing: CentralError.invalidAttribute(service.uuid))
            return nil
        }
        return serviceObject
    }
    
    func validateCharacteristic<T>(
        _ characteristic: Characteristic,
        for continuation: PeripheralContinuation<T, Error>
    ) -> CBCharacteristic? {
        guard let characteristicObject = self.cache.characteristics[characteristic] else {
            continuation.resume(throwing: CentralError.invalidAttribute(characteristic.uuid))
            return nil
        }
        return characteristicObject
    }
}

@available(macOS 10.5, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
internal extension DarwinCentral {
    
    @objc(GATTAsyncCentralManagerRestorableDelegate)
    class RestorableDelegate: Delegate {
        
        @objc
        func centralManager(_ centralManager: CBCentralManager, willRestoreState state: [String : Any]) {
            assert(self.central != nil)
            assert(self.central?.centralManager === centralManager)
            log("Will restore state: \(NSDictionary(dictionary: state).description)")
            // An array of peripherals for use when restoring the state of a central manager.
            if let peripherals = state[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
                for peripheralObject in peripherals {
                    self.central.cache.peripherals[Peripheral(peripheralObject)] = peripheralObject
                }
            }
        }
    }
    
    @objc(GATTAsyncCentralManagerDelegate)
    class Delegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
        
        private(set) weak var central: DarwinCentral!
        
        fileprivate init(_ central: DarwinCentral) {
            super.init()
            self.central = central
        }
        
        fileprivate func log(_ message: String) {
            self.central.log(message)
        }
        
        // MARK: - CBCentralManagerDelegate
        
        @objc(centralManagerDidUpdateState:)
        func centralManagerDidUpdateState(_ centralManager: CBCentralManager) {
            assert(self.central != nil)
            assert(self.central?.centralManager === centralManager)
            let state = unsafeBitCast(centralManager.state, to: DarwinBluetoothState.self)
            log("Did update state \(state)")
            self.central.continuation.state.yield(state)
        }
        
        @objc(centralManager:didDiscoverPeripheral:advertisementData:RSSI:)
        func centralManager(
            _ centralManager: CBCentralManager,
            didDiscover corePeripheral: CBPeripheral,
            advertisementData: [String : Any],
            rssi: NSNumber
        ) {
            assert(self.central != nil)
            assert(self.central?.centralManager === centralManager)
            if corePeripheral.delegate == nil {
                corePeripheral.delegate = self
            }
            let peripheral = Peripheral(corePeripheral)
            let advertisement = Advertisement(advertisementData)
            let scanResult = ScanData(
                peripheral: peripheral,
                date: Date(),
                rssi: rssi.doubleValue,
                advertisementData: advertisement,
                isConnectable: advertisement.isConnectable ?? false
            )
            // cache value
            self.central.cache.peripherals[peripheral] = corePeripheral
            // yield value to stream
            self.central.continuation.scan?.yield(scanResult)
        }
        
        #if os(iOS)
        func centralManager(
            _ central: CBCentralManager,
            connectionEventDidOccur event: CBConnectionEvent,
            for corePeripheral: CBPeripheral
        ) {
            log("\(corePeripheral.gattIdentifier.uuidString) connection event")
        }
        #endif
        
        @objc(centralManager:didConnectPeripheral:)
        func centralManager(
            _ centralManager: CBCentralManager,
            didConnect corePeripheral: CBPeripheral
        ) {
            log("Did connect to peripheral \(corePeripheral.gattIdentifier.uuidString)")
            assert(corePeripheral.state != .disconnected, "Should be connected")
            assert(self.central != nil)
            assert(self.central?.centralManager === centralManager)
            let peripheral = Peripheral(corePeripheral)
            guard let continuation = self.central.continuation.connect[peripheral] else {
                assertionFailure("Missing continuation")
                return
            }
            continuation.resume()
            self.central.continuation.connect[peripheral] = nil
        }
        
        @objc(centralManager:didFailToConnectPeripheral:error:)
        func centralManager(
            _ centralManager: CBCentralManager,
            didFailToConnect corePeripheral: CBPeripheral,
            error: Swift.Error?
        ) {
            log("Did fail to connect to peripheral \(corePeripheral.gattIdentifier.uuidString) (\(error!))")
            assert(self.central != nil)
            assert(self.central?.centralManager === centralManager)
            assert(corePeripheral.state != .connected)
            let peripheral = Peripheral(corePeripheral)
            guard let continuation = self.central.continuation.connect[peripheral] else {
                assertionFailure("Missing continuation")
                return
            }
            continuation.resume(throwing: error ?? CentralError.disconnected)
            self.central.continuation.connect[peripheral] = nil
        }
        
        @objc(centralManager:didDisconnectPeripheral:error:)
        func centralManager(
            _ central: CBCentralManager,
            didDisconnectPeripheral corePeripheral: CBPeripheral,
            error: Swift.Error?
        ) {
            if let error = error {
                log("Did disconnect peripheral \(corePeripheral.gattIdentifier.uuidString) due to error \(error.localizedDescription)")
            } else {
                log("Did disconnect peripheral \(corePeripheral.gattIdentifier.uuidString)")
            }
            
            let peripheral = Peripheral(corePeripheral)
            self.central.continuation.didDisconnect.yield(peripheral)
            
            // cancel all actions that require an active connection
            
            // discovering services
            self.central.continuation.discoverServices[peripheral]?
                .resume(throwing: CentralError.disconnected)
            self.central.continuation.discoverServices[peripheral] = nil
            // discover included services
            let discoverIncludedServices = self.central.continuation.discoverIncludedServices
                .filter { $0.key.peripheral == peripheral }
            if discoverIncludedServices.isEmpty == false {
                assert(discoverIncludedServices.count == 1, "\(discoverIncludedServices.count) discover included services")
                discoverIncludedServices
                    .forEach {
                        $0.value.resume(throwing: CentralError.disconnected)
                        self.central.continuation.discoverIncludedServices.removeValue(forKey: $0.key)
                    }
            }
            // discovering characteristics
            let discoverCharacteristics = self.central.continuation.discoverCharacteristics
                .filter { $0.key.peripheral == peripheral }
            if discoverCharacteristics.isEmpty == false {
                assert(discoverCharacteristics.count == 1, "\(discoverCharacteristics.count) discover characteristics")
                discoverCharacteristics
                    .forEach {
                        $0.value.resume(throwing: CentralError.disconnected)
                        self.central.continuation.discoverCharacteristics.removeValue(forKey: $0.key)
                    }
            }
            // read characteristic
            let readCharacteristic = self.central.continuation.readCharacteristic
                .filter { $0.key.peripheral == peripheral }
            if readCharacteristic.isEmpty == false {
                assert(readCharacteristic.count == 1, "\(readCharacteristic.count) read operations")
                readCharacteristic
                    .forEach {
                        $0.value.resume(throwing: CentralError.disconnected)
                        self.central.continuation.readCharacteristic.removeValue(forKey: $0.key)
                    }
            }
            // write characteristic
            let writeCharacteristic = self.central.continuation.writeCharacteristic
                .filter { $0.key.peripheral == peripheral }
            if writeCharacteristic.isEmpty == false {
                assert(writeCharacteristic.count == 1, "\(writeCharacteristic.count) write operations")
                writeCharacteristic
                    .forEach {
                        $0.value.resume(throwing: CentralError.disconnected)
                        self.central.continuation.writeCharacteristic.removeValue(forKey: $0.key)
                    }
            }
            // write without response
            self.central.continuation.isReadyToWriteWithoutResponse[peripheral]?
                .resume(throwing: CentralError.disconnected)
            // notifications
            let notifications = self.central.continuation.notificationStream
                .filter { $0.key.peripheral == peripheral }
            if notifications.isEmpty == false {
                assert(notifications.count == 1, "\(notifications.count) notification streams")
                notifications
                    .forEach {
                        $0.value.finish(throwing: CentralError.disconnected)
                        self.central.continuation.notificationStream.removeValue(forKey: $0.key)
                    }
            }
            // disable notifications
            let stopNotification = self.central.continuation.stopNotification
                .filter { $0.key.peripheral == peripheral }
            if stopNotification.isEmpty == false {
                assert(stopNotification.count == 1, "\(stopNotification.count) disable notifications")
                stopNotification
                    .forEach {
                        $0.value.resume(throwing: CentralError.disconnected)
                        self.central.continuation.stopNotification.removeValue(forKey: $0.key)
                    }
            }
            // read descriptor
            let readDescriptor = self.central.continuation.readDescriptor
                .filter { $0.key.peripheral == peripheral }
            if readDescriptor.isEmpty == false {
                assert(readCharacteristic.count == 1, "\(readDescriptor.count) read descriptor operations")
                readDescriptor
                    .forEach {
                        $0.value.resume(throwing: CentralError.disconnected)
                        self.central.continuation.readDescriptor.removeValue(forKey: $0.key)
                    }
            }
            // write descriptor
            let writeDescriptor = self.central.continuation.writeDescriptor
                .filter { $0.key.peripheral == peripheral }
            if writeDescriptor.isEmpty == false {
                assert(writeDescriptor.count == 1, "\(writeDescriptor.count) write descriptor operations")
                writeDescriptor
                    .forEach {
                        $0.value.resume(throwing: CentralError.disconnected)
                        self.central.continuation.writeDescriptor.removeValue(forKey: $0.key)
                    }
            }
        }
        
        // MARK: - CBPeripheralDelegate
        
        @objc(peripheral:didDiscoverServices:)
        func peripheral(
            _ corePeripheral: CBPeripheral,
            didDiscoverServices error: Swift.Error?
        ) {
            
            if let error = error {
                log("Peripheral \(corePeripheral.gattIdentifier.uuidString) failed discovering services (\(error))")
            } else {
                log("Peripheral \(corePeripheral.gattIdentifier.uuidString) did discover \(corePeripheral.services?.count ?? 0) services")
            }
            
            let peripheral = Peripheral(corePeripheral)
            guard let continuation = self.central.continuation.discoverServices[peripheral] else {
                assertionFailure("Missing continuation")
                return
            }
            if let error = error {
                continuation.resume(throwing: error)
            } else {
                let serviceObjects = corePeripheral.services ?? []
                let services = serviceObjects.map { serviceObject in
                    Service(
                        service: serviceObject,
                        peripheral: corePeripheral
                    )
                }
                for (index, service) in services.enumerated() {
                    self.central.cache.services[service] = serviceObjects[index]
                }
                continuation.resume(returning: services)
            }
            // remove callback
            self.central.continuation.discoverServices[peripheral] = nil
        }
        
        @objc(peripheral:didDiscoverCharacteristicsForService:error:)
        func peripheral(
            _ peripheralObject: CBPeripheral,
            didDiscoverCharacteristicsFor serviceObject: CBService,
            error: Error?
        ) {
            
            if let error = error {
                log("Peripheral \(peripheralObject.gattIdentifier.uuidString) failed discovering characteristics (\(error))")
            } else {
                log("Peripheral \(peripheralObject.gattIdentifier.uuidString) did discover \(serviceObject.characteristics?.count ?? 0) characteristics for service \(serviceObject.uuid.uuidString)")
            }
            
            let service = Service(service: serviceObject, peripheral: peripheralObject)
            guard let continuation = self.central.continuation.discoverCharacteristics[service] else {
                assertionFailure("Missing continuation")
                return
            }
            if let error = error {
                continuation.resume(throwing: error)
            } else {
                let characteristicObjects = serviceObject.characteristics ?? []
                let characteristics = characteristicObjects.map { characteristicObject in
                    Characteristic(
                        characteristic: characteristicObject,
                        peripheral: peripheralObject
                    )
                }
                for (index, characteristic) in characteristics.enumerated() {
                    self.central.cache.characteristics[characteristic] = characteristicObjects[index]
                }
                continuation.resume(returning: characteristics)
            }
            // remove callback
            self.central.continuation.discoverCharacteristics[service] = nil
        }
        
        @objc(peripheral:didUpdateValueForCharacteristic:error:)
        func peripheral(
            _ peripheralObject: CBPeripheral,
            didUpdateValueFor characteristicObject: CBCharacteristic,
            error: Error?
        ) {
            
            if let error = error {
                log("Peripheral \(peripheralObject.gattIdentifier.uuidString) failed reading characteristic (\(error))")
            } else {
                log("Peripheral \(peripheralObject.gattIdentifier.uuidString) did update value for characteristic \(characteristicObject.uuid.uuidString)")
            }
            
            let data = characteristicObject.value ?? Data()
            let characteristic = Characteristic(
                characteristic: characteristicObject,
                peripheral: peripheralObject
            )
            
            // read value
            if let continuation = self.central.continuation.readCharacteristic[characteristic] {
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: data)
                }
                self.central.continuation.readCharacteristic[characteristic] = nil
            }
            // notification
            else if let stream = self.central.continuation.notificationStream[characteristic] {
                assert(error == nil, "Notifications should never fail")
                stream.yield(data)
                self.central.continuation.notificationStream[characteristic] = nil
            } else {
                assertionFailure("Missing continuation, not read or notification")
            }
        }
        
        @objc(peripheral:didWriteValueForCharacteristic:error:)
        func peripheral(
            _ peripheralObject: CBPeripheral,
            didWriteValueFor characteristicObject: CBCharacteristic,
            error: Swift.Error?
        ) {
            
            if let error = error {
                log("Peripheral \(peripheralObject.gattIdentifier.uuidString) failed writing characteristic (\(error))")
            } else {
                log("Peripheral \(peripheralObject.gattIdentifier.uuidString) did write value for characteristic \(characteristicObject.uuid.uuidString)")
            }
            
            let characteristic = Characteristic(
                characteristic: characteristicObject,
                peripheral: peripheralObject
            )
            // should only be called for write with response
            guard let continuation = self.central.continuation.writeCharacteristic[characteristic] else {
                assertionFailure("Missing continuation")
                return
            }
            if let error = error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume()
            }
            self.central.continuation.writeCharacteristic[characteristic] = nil
        }
        
        @objc
        func peripheral(
            _ peripheralObject: CBPeripheral,
            didUpdateNotificationStateFor characteristicObject: CBCharacteristic,
            error: Swift.Error?
        ) {
            if let error = error {
                log("Peripheral \(peripheralObject.gattIdentifier.uuidString) failed setting notifications for characteristic (\(error))")
            } else {
                log("Peripheral \(peripheralObject.gattIdentifier.uuidString) did update notification state for characteristic \(characteristicObject.uuid.uuidString)")
            }
            
            let characteristic = Characteristic(
                characteristic: characteristicObject,
                peripheral: peripheralObject
            )
            if characteristicObject.isNotifying {
                guard let continuation = self.central.continuation.notificationStream[characteristic] else {
                    assertionFailure("Missing continuation")
                    return
                }
                if let error = error {
                    continuation.finish(throwing: error)
                    self.central.continuation.notificationStream[characteristic] = nil
                } else {
                    // do nothing until notification is recieved.
                }
            } else {
                guard let continuation = self.central.continuation.stopNotification[characteristic] else {
                    assertionFailure("Missing continuation")
                    return
                }
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
                self.central.continuation.stopNotification[characteristic] = nil
            }
        }
        
        func peripheralIsReady(toSendWriteWithoutResponse peripheralObject: CBPeripheral) {
            
            log("Peripheral \(peripheralObject.gattIdentifier.uuidString) is ready to send write without response")
            
            let peripheral = Peripheral(peripheralObject)
            if let continuation = self.central.continuation.isReadyToWriteWithoutResponse[peripheral] {
                continuation.resume()
                self.central.continuation.isReadyToWriteWithoutResponse[peripheral] = nil
            }
        }
        
        func peripheralDidUpdateName(_ peripheralObject: CBPeripheral) {
            log("Peripheral \(peripheralObject.gattIdentifier.uuidString) updated name \(peripheralObject.name ?? "")")
        }
        
        func peripheral(_ peripheralObject: CBPeripheral, didReadRSSI rssiObject: NSNumber, error: Error?) {
            if let error = error {
                log("Peripheral \(peripheralObject.gattIdentifier.uuidString) failed to read RSSI (\(error))")
            } else {
                log("Peripheral \(peripheralObject.gattIdentifier.uuidString) did read RSSI \(rssiObject.description)")
            }
            let peripheral = Peripheral(peripheralObject)
            guard let continuation = self.central.continuation.readRSSI[peripheral] else {
                assertionFailure("Missing continuation")
                return
            }
            if let error = error {
                continuation.resume(throwing: error)
            } else {
                guard let rssi = Bluetooth.RSSI(rawValue: rssiObject.int8Value) else {
                    assertionFailure("Invalid RSSI \(rssiObject)")
                    continuation.resume(returning: RSSI(rawValue: -127)!)
                    self.central.continuation.readRSSI[peripheral] = nil
                    return
                }
                continuation.resume(returning: rssi)
            }
            self.central.continuation.readRSSI[peripheral] = nil
        }
        
        func peripheral(
            _ peripheralObject: CBPeripheral,
            didDiscoverIncludedServicesFor serviceObject: CBService,
            error: Error?
        ) {
            if let error = error {
                log("Peripheral \(peripheralObject.gattIdentifier.uuidString) failed discovering included services for service \(serviceObject.uuid.description) (\(error))")
            } else {
                log("Peripheral \(peripheralObject.gattIdentifier.uuidString) did discover \(serviceObject.includedServices?.count ?? 0) included services for service \(serviceObject.uuid.uuidString)")
            }
                        
            let service = Service(
                service: serviceObject,
                peripheral: peripheralObject
            )
            guard let continuation = self.central.continuation.discoverIncludedServices[service] else {
                assertionFailure("Missing continuation")
                return
            }
            if let error = error {
                continuation.resume(throwing: error)
            } else {
                let services = (serviceObject.includedServices ?? []).map { serviceObject in
                    Service(
                        service: serviceObject,
                        peripheral: peripheralObject
                    )
                }
                continuation.resume(returning: services)
            }
            // remove callback
            self.central.continuation.discoverIncludedServices[service] = nil
        }
        
        func peripheral(_ peripheralObject: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
            log("Peripheral \(peripheralObject.gattIdentifier.uuidString) did modify \(invalidatedServices.count) services")
            // TODO: Try to rediscover services
        }
        
        func peripheral(_ peripheralObject: CBPeripheral, didDiscoverDescriptorsFor characteristicObject: CBCharacteristic, error: Error?) {
            
            if let error = error {
                log("Peripheral \(peripheralObject.gattIdentifier.uuidString) failed discovering descriptors for characteristic \(characteristicObject.uuid.uuidString) (\(error))")
            } else {
                log("Peripheral \(peripheralObject.gattIdentifier.uuidString) did discover \(characteristicObject.descriptors?.count ?? 0) descriptors for characteristic \(characteristicObject.uuid.uuidString)")
            }
            
            let peripheral = Peripheral(peripheralObject)
            guard let continuation = self.central.continuation.discoverDescriptors[peripheral] else {
                assertionFailure("Missing continuation")
                return
            }
            if let error = error {
                continuation.resume(throwing: error)
            } else {
                let descriptors = (characteristicObject.descriptors ?? []).map { descriptorObject in
                    Descriptor(
                        descriptor: descriptorObject,
                        peripheral: peripheralObject
                    )
                }
                continuation.resume(returning: descriptors)
            }
            // remove callback
            self.central.continuation.discoverDescriptors[peripheral] = nil
        }
        
        func peripheral(
            _ peripheralObject: CBPeripheral,
            didWriteValueFor descriptorObject: CBDescriptor,
            error: Error?
        ) {
            
            if let error = error {
                log("Peripheral \(peripheralObject.gattIdentifier.uuidString) failed writing descriptor \(descriptorObject.uuid.uuidString) (\(error))")
            } else {
                log("Peripheral \(peripheralObject.gattIdentifier.uuidString) did write value for descriptor \(descriptorObject.uuid.uuidString)")
            }
            
            let descriptor = Descriptor(
                descriptor: descriptorObject,
                peripheral: peripheralObject
            )
            guard let continuation = self.central.continuation.writeDescriptor[descriptor] else {
                assertionFailure("Missing continuation")
                return
            }
            if let error = error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume()
            }
            self.central.continuation.writeDescriptor[descriptor] = nil
        }
        
        func peripheral(
            _ peripheralObject: CBPeripheral,
            didUpdateValueFor descriptorObject: CBDescriptor,
            error: Error?
        ) {
            
            if let error = error {
                log("Peripheral \(peripheralObject.gattIdentifier.uuidString) failed updating value for descriptor \(descriptorObject.uuid.uuidString) (\(error))")
            } else {
                log("Peripheral \(peripheralObject.gattIdentifier.uuidString) did update value for descriptor \(descriptorObject.uuid.uuidString)")
            }
            
            let descriptor = Descriptor(
                descriptor: descriptorObject,
                peripheral: peripheralObject
            )
            guard let continuation = self.central.continuation.readDescriptor[descriptor] else {
                assertionFailure("Missing continuation")
                return
            }
            if let error = error {
                continuation.resume(throwing: error)
            } else {
                let data: Data
                if let descriptor = DarwinDescriptor(descriptorObject) {
                    data = descriptor.data
                } else if let dataObject = descriptorObject.value as? NSData {
                    data = dataObject as Data
                } else {
                    data = Data()
                }
                continuation.resume(returning: data)
            }
            self.central.continuation.readDescriptor[descriptor] = nil
        }
    }
}

@available(macOS 10.5, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
internal extension Service where ID == ObjectIdentifier, Peripheral == DarwinCentral.Peripheral {
    
    init(
        service serviceObject: CBService,
        peripheral peripheralObject: CBPeripheral
    ) {
        self.init(
            id: ObjectIdentifier(serviceObject),
            uuid: BluetoothUUID(serviceObject.uuid),
            peripheral: DarwinCentral.Peripheral(peripheralObject),
            isPrimary: serviceObject.isPrimary
        )
    }
}

@available(macOS 10.5, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
internal extension Characteristic where ID == ObjectIdentifier, Peripheral == DarwinCentral.Peripheral {
    
    init(
        characteristic characteristicObject: CBCharacteristic,
        peripheral peripheralObject: CBPeripheral
    ) {
        self.init(
            id: ObjectIdentifier(characteristicObject),
            uuid: BluetoothUUID(characteristicObject.uuid),
            peripheral: DarwinCentral.Peripheral(peripheralObject),
            properties: .init(rawValue: numericCast(characteristicObject.properties.rawValue))
        )
    }
}

@available(macOS 10.5, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
internal extension Descriptor where ID == ObjectIdentifier, Peripheral == DarwinCentral.Peripheral {
    
    init(
        descriptor descriptorObject: CBDescriptor,
        peripheral peripheralObject: CBPeripheral
    ) {
        self.init(
            id: ObjectIdentifier(descriptorObject),
            uuid: BluetoothUUID(descriptorObject.uuid),
            peripheral: DarwinCentral.Peripheral(peripheralObject)
        )
    }
}

internal extension CBPeripheral {
    
    var mtuLength: NSNumber {
        return self.value(forKey: "mtuLength") as! NSNumber
    }
}

#endif
