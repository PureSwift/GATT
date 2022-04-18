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
    
    public var log: ((String) -> ())?
    
    public let options: Options
    
    public var state: DarwinBluetoothState {
        get async {
            return await withUnsafeContinuation { [unowned self] continuation in
                self.async { [unowned self] in
                    let state = unsafeBitCast(self.centralManager.state, to: DarwinBluetoothState.self)
                    continuation.resume(returning: state)
                }
            }
        }
    }
    
    /// Currently scanned devices, or restored devices.
    public var peripherals: Set<Peripheral> {
        get async {
            return await withUnsafeContinuation { [unowned self] continuation in
                self.async { [unowned self] in
                    let peripherals = Set(self.cache.peripherals.keys)
                    continuation.resume(returning: peripherals)
                }
            }
        }
    }
    
    private var centralManager: CBCentralManager!
    
    private var delegate: Delegate!
    
    private let queue = DispatchQueue(label: "org.pureswift.DarwinGATT.DarwinCentral")
    
    fileprivate var cache = Cache()
    
    fileprivate var continuation = Continuation()
    
    // MARK: - Initialization
    
    /// Initialize with the specified options.
    ///
    /// - Parameter options: An optional dictionary containing initialization options for a central manager.
    /// For available options, see [Central Manager Initialization Options](apple-reference-documentation://ts1667590).
    public init(
        options: Options = Options()
    ) {
        self.options = options
        self.delegate = options.restoreIdentifier == nil ? Delegate(self) : RestorableDelegate(self)
        self.centralManager = CBCentralManager(
            delegate: self.delegate,
            queue: queue,
            options: options.dictionary
        )
        continuation.scan = Queue<Operation.Scan> { [unowned self] in
            self.execute($0)
            return true
        }
    }
    
    // MARK: - Methods
    
    /// Scans for peripherals that are advertising services.
    public func scan(
        filterDuplicates: Bool = true
    ) async throws -> AsyncCentralScan<DarwinCentral> {
        return scan(with: [], filterDuplicates: filterDuplicates)
    }
    
    /// Scans for peripherals that are advertising services.
    public func scan(
        with services: Set<BluetoothUUID>,
        filterDuplicates: Bool = true
    ) -> AsyncCentralScan<DarwinCentral> {
        return AsyncCentralScan(onTermination: { [weak self] in
            guard let self = self else { return }
            self.async {
                guard let _ = self.continuation.scan.current else {
                    return // not currently scanning
                }
                self.continuation.scan.pop { operation in
                    self.centralManager.stopScan()
                    self.log?("Discovered \(self.cache.peripherals.count) peripherals")
                }
            }
            
        }) { continuation in
            self.async {
                // disconnect all first
                self._disconnectAll()
                // queue scan operation
                let operations = Operation.Scan(
                    services: services,
                    filterDuplicates: filterDuplicates,
                    continuation: continuation
                )
                self.continuation.scan.push(operations)
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
        self.async { [weak self] in
            guard let self = self else { return }
            if self._disconnect(peripheral) {
                self.log?("Will disconnect \(peripheral)")
            }
        }
    }
    
    private func _disconnect(_ peripheral: Peripheral) -> Bool {
        guard let peripheralObject = self.cache.peripherals[peripheral] else {
            return false
        }
        self.centralManager.cancelPeripheralConnection(peripheralObject)
        return true
    }
    
    public func disconnectAll() {
        self.log?("Will disconnect all")
        self.async { [weak self] in
            guard let self = self else { return }
            self._disconnectAll()
        }
    }
    
    private func _disconnectAll() {
        for peripheralObject in self.cache.peripherals.values {
            self.centralManager.cancelPeripheralConnection(peripheralObject)
        }
    }
    
    public func discoverServices(
        _ services: Set<BluetoothUUID> = [],
        for peripheral: Peripheral
    ) async throws -> [DarwinCentral.Service] {
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
        return try await withThrowingContinuation(for: characteristic.peripheral) { [weak self] continuation in
            guard let self = self else { return }
            self.async {
                let operation = Operation.ReadCharacteristic(
                    characteristic: characteristic,
                    continuation: continuation
                )
                self.enqueue(.readCharacteristic(operation), for: characteristic.peripheral)
            }
        }
    }
    
    public func writeValue(
        _ data: Data,
        for characteristic: DarwinCentral.Characteristic,
        withResponse: Bool = true
    ) async throws {
        if withResponse == false  {
            try await waitUntilCanSendWriteWithoutResponse(for: characteristic.peripheral)
        }
        try await write(data, withResponse: withResponse, for: characteristic)
    }
    
    public func discoverDescriptors(
        for characteristic: DarwinCentral.Characteristic
    ) async throws -> [DarwinCentral.Descriptor] {
        return try await withThrowingContinuation(for: characteristic.peripheral) { [weak self] continuation in
            guard let self = self else { return }
            self.async {
                let operation = Operation.DiscoverDescriptors(
                    characteristic: characteristic,
                    continuation: continuation
                )
                self.enqueue(.discoverDescriptors(operation), for: characteristic.peripheral)
            }
        }
    }
    
    public func readValue(
        for descriptor: DarwinCentral.Descriptor
    ) async throws -> Data {
        return try await withThrowingContinuation(for: descriptor.peripheral) { [weak self] continuation in
            guard let self = self else { return }
            self.async {
                let operation = Operation.ReadDescriptor(
                    descriptor: descriptor,
                    continuation: continuation
                )
                self.enqueue(.readDescriptor(operation), for: descriptor.peripheral)
            }
        }
    }
    
    public func writeValue(
        _ data: Data,
        for descriptor: DarwinCentral.Descriptor
    ) async throws {
        return try await withThrowingContinuation(for: descriptor.peripheral) { [weak self] continuation in
            guard let self = self else { return }
            self.async {
                let operation = Operation.WriteDescriptor(
                    descriptor: descriptor,
                    data: data,
                    continuation: continuation
                )
                self.enqueue(.writeDescriptor(operation), for: descriptor.peripheral)
            }
        }
    }
    
    public func notify(
        for characteristic: DarwinCentral.Characteristic
    ) async throws -> AsyncCentralNotifications<DarwinCentral> {
        // enable notifications
        try await self.setNotification(true, for: characteristic)
        // central
        return AsyncCentralNotifications(onTermination: {
            Task(priority: .high) { [weak self] in
                guard let self = self else { return }
                // disable notifications
                do { try await self.setNotification(false, for: characteristic) }
                catch CentralError.disconnected {
                    return
                }
                catch {
                    self.log?("Unable to stop notifications for \(characteristic.uuid). \(error.localizedDescription)")
                }
                // remove notification stream
                self.async { [weak self] in
                    guard let self = self else { return }
                    let context = self.continuation(for: characteristic.peripheral)
                    context.notificationStream[characteristic.id] = nil
                }
            }
        }, { continuation in
            self.async { [unowned self] in
                // store continuation
                let context = self.continuation(for: characteristic.peripheral)
                assert(context.notificationStream[characteristic.id] == nil)
                context.notificationStream[characteristic.id] = continuation
            }
        })
    }
    
    public func maximumTransmissionUnit(for peripheral: Peripheral) async throws -> MaximumTransmissionUnit {
        self.log?("Will read MTU for \(peripheral)")
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
    
    public func rssi(for peripheral: Peripheral) async throws -> RSSI {
        return try await withThrowingContinuation(for: peripheral) { [weak self] continuation in
            guard let self = self else { return }
            self.async {
                let operation = Operation.ReadRSSI(
                    peripheral: peripheral,
                    continuation: continuation
                )
                self.enqueueReadRSSI(operation, for: peripheral)
            }
        }
    }
    
    // MARK - Private Methods
    
    @inline(__always)
    private func async(_ body: @escaping () -> ()) {
        queue.async(execute: body)
    }
    
    private func continuation(for peripheral: Peripheral) -> PeripheralContinuationContext {
        if let context = self.continuation.peripherals[peripheral] {
            return context
        } else {
            let context = PeripheralContinuationContext(self)
            self.continuation.peripherals[peripheral] = context
            return context
        }
    }
    
    private func enqueue(_ operation: Operation, for peripheral: Peripheral) {
        let context = continuation(for: peripheral)
        context.queue.push(operation)
    }
    
    private func dequeue(for peripheral: Peripheral, _ body: (Operation) -> ()) {
        guard let context = self.continuation.peripherals[peripheral] else {
            assertionFailure("Missing context")
            return
        }
        context.queue.pop(body)
    }
    
    private func enqueueReadRSSI(_ operation: Operation.ReadRSSI, for peripheral: Peripheral) {
        let context = continuation(for: peripheral)
        context.readRSSI.push(operation)
    }
    
    private func dequeueReadRSSI(for peripheral: Peripheral, _ body: (Operation.ReadRSSI) -> ()) {
        guard let context = self.continuation.peripherals[peripheral] else {
            assertionFailure("Missing context")
            return
        }
        context.readRSSI.pop(body)
    }
    
    private func write(
        _ data: Data,
        withResponse: Bool,
        for characteristic: DarwinCentral.Characteristic
    ) async throws {
        return try await withThrowingContinuation(for: characteristic.peripheral) { [weak self] continuation in
            guard let self = self else { return }
            self.async {
                let operation = Operation.WriteCharacteristic(
                    characteristic: characteristic,
                    data: data,
                    withResponse: withResponse,
                    continuation: continuation
                )
                self.enqueue(.writeCharacteristic(operation), for: characteristic.peripheral)
            }
        }
    }
    
    @available(*, deprecated)
    private func canSendWriteWithoutResponse(
        for peripheral: Peripheral
    ) async throws -> Bool {
        return try await withThrowingContinuation(for: peripheral) { [weak self] continuation in
            guard let self = self else { return }
            self.async {
                // get peripheral
                guard let peripheralObject = self.validatePeripheral(peripheral, for: continuation) else {
                    return
                }
                // yield value
                let value = peripheralObject.canSendWriteWithoutResponse
                continuation.resume(returning: value)
            }
        }
    }
    
    private func waitUntilCanSendWriteWithoutResponse(
        for peripheral: Peripheral
    ) async throws {
        return try await withThrowingContinuation(for: peripheral) { [weak self] continuation in
            guard let self = self else { return }
            self.async {
                let operation = Operation.WriteWithoutResponseReady(
                    peripheral: peripheral,
                    continuation: continuation
                )
                self.enqueue(.isReadyToWriteWithoutResponse(operation), for: peripheral)
            }
        }
    }
    
    private func setNotification(
        _ isEnabled: Bool,
        for characteristic: Characteristic
    ) async throws {
        return try await withThrowingContinuation(for: characteristic.peripheral) { [weak self] continuation in
            guard let self = self else { return }
            self.async {
                let operation = Operation.NotificationState(
                    characteristic: characteristic,
                    isEnabled: isEnabled,
                    continuation: continuation
                )
                self.enqueue(.setNotification(operation), for: characteristic.peripheral)
            }
        }
    }
    
    private func _maximumTransmissionUnit(for peripheral: Peripheral) throws -> MaximumTransmissionUnit {
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
            self.id = peripheral.id
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
        
        internal var dictionary: [String: Any] {
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
private extension DarwinCentral {
    
    struct Cache {
        var peripherals = [Peripheral: CBPeripheral]()
        var services = [DarwinCentral.Service: CBService]()
        var characteristics = [DarwinCentral.Characteristic: CBCharacteristic]()
        var descriptors = [DarwinCentral.Descriptor: CBDescriptor]()
    }
    
    final class Continuation {
        
        var scan: Queue<Operation.Scan>!
        var peripherals = [DarwinCentral.Peripheral: PeripheralContinuationContext]()
        fileprivate init() { }
    }
    
    final class PeripheralContinuationContext {
        
        var queue: Queue<Operation>
        var notificationStream = [AttributeID: AsyncIndefiniteStream<Data>.Continuation]()
        var readRSSI: Queue<Operation.ReadRSSI>
        
        fileprivate init(_ central: DarwinCentral) {
            self.queue = Queue<Operation> { [unowned central] in
                central.execute($0)
            }
            self.readRSSI = Queue<Operation.ReadRSSI> { [unowned central] in
                central.execute($0)
            }
        }
    }
}

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
    
    func resume(throwing error: Swift.Error, function: String = #function) {
        switch self {
        case let .connect(operation):
            operation.continuation.resume(throwing: error)
        case let .discoverServices(operation):
            operation.continuation.resume(throwing: error)
        case let .discoverIncludedServices(operation):
            operation.continuation.resume(throwing: error)
        case let .discoverCharacteristics(operation):
            operation.continuation.resume(throwing: error)
        case let .writeCharacteristic(operation):
            operation.continuation.resume(throwing: error)
        case let .readCharacteristic(operation):
            operation.continuation.resume(throwing: error)
        case let .discoverDescriptors(operation):
            operation.continuation.resume(throwing: error)
        case let .readDescriptor(operation):
            operation.continuation.resume(throwing: error)
        case let .writeDescriptor(operation):
            operation.continuation.resume(throwing: error)
        case let .isReadyToWriteWithoutResponse(operation):
            operation.continuation.resume(throwing: error)
        case let .setNotification(operation):
            operation.continuation.resume(throwing: error)
        }
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
        let data: Data
        let withResponse: Bool
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
        let data: Data
        let continuation: PeripheralContinuation<(), Error>
    }
    
    struct WriteWithoutResponseReady {
        let peripheral: DarwinCentral.Peripheral
        let continuation: PeripheralContinuation<(), Error>
    }
    
    struct NotificationState {
        let characteristic: DarwinCentral.Characteristic
        let isEnabled: Bool
        let continuation: PeripheralContinuation<(), Error>
    }
    
    struct ReadRSSI {
        let peripheral: DarwinCentral.Peripheral
        let continuation: PeripheralContinuation<RSSI, Error>
    }
    
    struct Scan {
        let services: Set<BluetoothUUID>
        let filterDuplicates: Bool
        let continuation: AsyncIndefiniteStream<ScanData<DarwinCentral.Peripheral, DarwinCentral.Advertisement>>.Continuation
    }
}

@available(macOS 10.5, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
internal extension DarwinCentral {
    
    /// Executes an operation and informs whether a continuation is pending.
    func execute(_ operation: DarwinCentral.Operation) -> Bool {
        switch operation {
        case let .connect(operation):
            return execute(operation)
        case let .discoverServices(operation):
            return execute(operation)
        case let .discoverIncludedServices(operation):
            return execute(operation)
        case let .discoverCharacteristics(operation):
            return execute(operation)
        case let .readCharacteristic(operation):
            return execute(operation)
        case let .writeCharacteristic(operation):
            return execute(operation)
        case let .discoverDescriptors(operation):
            return execute(operation)
        case let .readDescriptor(operation):
            return execute(operation)
        case let .writeDescriptor(operation):
            return execute(operation)
        case let .setNotification(operation):
            return execute(operation)
        case let .isReadyToWriteWithoutResponse(operation):
            return execute(operation)
        }
    }
    
    func execute(_ operation: Operation.Connect) -> Bool {
        log?("Will connect to \(operation.peripheral)")
        // check power on
        guard validateState(.poweredOn, for: operation.continuation) else {
            return false
        }
        // get peripheral
        guard let peripheralObject = validatePeripheral(operation.peripheral, for: operation.continuation) else {
            return false
        }
        // connect
        self.centralManager.connect(peripheralObject, options: operation.options)
        return true
    }
    
    func execute(_ operation: Operation.DiscoverServices) -> Bool {
        log?("Peripheral \(operation.peripheral) will discover services")
        // check power on
        guard validateState(.poweredOn, for: operation.continuation) else {
            return false
        }
        // get peripheral
        guard let peripheralObject = validatePeripheral(operation.peripheral, for: operation.continuation) else {
            return false
        }
        // check connected
        guard validateConnected(peripheralObject, for: operation.continuation) else {
            return false
        }
        // discover
        let serviceUUIDs = operation.services.isEmpty ? nil : operation.services.map { CBUUID($0) }
        peripheralObject.discoverServices(serviceUUIDs)
        return true
    }
    
    func execute(_ operation: Operation.DiscoverIncludedServices) -> Bool {
        log?("Peripheral \(operation.service.peripheral) will discover included services of service \(operation.service.uuid)")
        // check power on
        guard validateState(.poweredOn, for: operation.continuation) else {
            return false
        }
        // get peripheral
        guard let peripheralObject = validatePeripheral(operation.service.peripheral, for: operation.continuation) else {
            return false
        }
        // check connected
        guard validateConnected(peripheralObject, for: operation.continuation) else {
            return false
        }
        // get service
        guard let serviceObject = validateService(operation.service, for: operation.continuation) else {
            return false
        }
        let serviceUUIDs = operation.services.isEmpty ? nil : operation.services.map { CBUUID($0) }
        peripheralObject.discoverIncludedServices(serviceUUIDs, for: serviceObject)
        return true
    }
    
    func execute(_ operation: Operation.DiscoverCharacteristics) -> Bool {
        log?("Peripheral \(operation.service.peripheral) will discover characteristics of service \(operation.service.uuid)")
        // check power on
        guard validateState(.poweredOn, for: operation.continuation) else {
            return false
        }
        // get peripheral
        guard let peripheralObject = validatePeripheral(operation.service.peripheral, for: operation.continuation) else {
            return false
        }
        // check connected
        guard validateConnected(peripheralObject, for: operation.continuation) else {
            return false
        }
        // get service
        guard let serviceObject = validateService(operation.service, for: operation.continuation) else {
            return false
        }
        // discover
        let characteristicUUIDs = operation.characteristics.isEmpty ? nil : operation.characteristics.map { CBUUID($0) }
        peripheralObject.discoverCharacteristics(characteristicUUIDs, for: serviceObject)
        return true
    }
    
    func execute(_ operation: Operation.ReadCharacteristic) -> Bool {
        log?("Peripheral \(operation.characteristic.peripheral) will read characteristic \(operation.characteristic.uuid)")
        // check power on
        guard validateState(.poweredOn, for: operation.continuation) else {
            return false
        }
        // get peripheral
        guard let peripheralObject = validatePeripheral(operation.characteristic.peripheral, for: operation.continuation) else {
            return false
        }
        // check connected
        guard validateConnected(peripheralObject, for: operation.continuation) else {
            return false
        }
        // get characteristic
        guard let characteristicObject = validateCharacteristic(operation.characteristic, for: operation.continuation) else {
            return false
        }
        // read value
        peripheralObject.readValue(for: characteristicObject)
        return true
    }
    
    func execute(_ operation: Operation.WriteCharacteristic) -> Bool {
        log?("Peripheral \(operation.characteristic.peripheral) will write characteristic \(operation.characteristic.uuid)")
        // check power on
        guard validateState(.poweredOn, for: operation.continuation) else {
            return false
        }
        // get peripheral
        guard let peripheralObject = validatePeripheral(operation.characteristic.peripheral, for: operation.continuation) else {
            return false
        }
        // check connected
        guard validateConnected(peripheralObject, for: operation.continuation) else {
            return false
        }
        // get characteristic
        guard let characteristicObject = validateCharacteristic(operation.characteristic, for: operation.continuation) else {
            return false
        }
        assert(operation.withResponse || peripheralObject.canSendWriteWithoutResponse, "Cannot write without response")
        // calls `peripheral:didWriteValueForCharacteristic:error:` only
        // if you specified the write type as `.withResponse`.
        let writeType: CBCharacteristicWriteType = operation.withResponse ? .withResponse : .withoutResponse
        peripheralObject.writeValue(operation.data, for: characteristicObject, type: writeType)
        guard operation.withResponse else {
            operation.continuation.resume()
            return false
        }
        return true
    }
    
    func execute(_ operation: Operation.DiscoverDescriptors) -> Bool {
        log?("Peripheral \(operation.characteristic.peripheral) will discover descriptors of characteristic \(operation.characteristic.uuid)")
        // check power on
        guard validateState(.poweredOn, for: operation.continuation) else {
            return false
        }
        // get peripheral
        guard let peripheralObject = validatePeripheral(operation.characteristic.peripheral, for: operation.continuation) else {
            return false
        }
        // check connected
        guard validateConnected(peripheralObject, for: operation.continuation) else {
            return false
        }
        // get characteristic
        guard let characteristicObject = validateCharacteristic(operation.characteristic, for: operation.continuation) else {
            return false
        }
        // discover
        peripheralObject.discoverDescriptors(for: characteristicObject)
        return true
    }
    
    func execute(_ operation: Operation.ReadDescriptor) -> Bool {
        log?("Peripheral \(operation.descriptor.peripheral) will read descriptor \(operation.descriptor.uuid)")
        // check power on
        guard validateState(.poweredOn, for: operation.continuation) else {
            return false
        }
        // get peripheral
        guard let peripheralObject = validatePeripheral(operation.descriptor.peripheral, for: operation.continuation) else {
            return false
        }
        // check connected
        guard validateConnected(peripheralObject, for: operation.continuation) else {
            return false
        }
        // get descriptor
        guard let descriptorObject = validateDescriptor(operation.descriptor, for: operation.continuation) else {
            return false
        }
        // write
        peripheralObject.readValue(for: descriptorObject)
        return true
    }
    
    func execute(_ operation: Operation.WriteDescriptor) -> Bool {
        log?("Peripheral \(operation.descriptor.peripheral) will write descriptor \(operation.descriptor.uuid)")
        // check power on
        guard validateState(.poweredOn, for: operation.continuation) else {
            return false
        }
        // get peripheral
        guard let peripheralObject = validatePeripheral(operation.descriptor.peripheral, for: operation.continuation) else {
            return false
        }
        // check connected
        guard validateConnected(peripheralObject, for: operation.continuation) else {
            return false
        }
        // get descriptor
        guard let descriptorObject = validateDescriptor(operation.descriptor, for: operation.continuation) else {
            return false
        }
        // write
        peripheralObject.writeValue(operation.data, for: descriptorObject)
        return true
    }
    
    func execute(_ operation: Operation.WriteWithoutResponseReady) -> Bool {
        // get peripheral
        guard let peripheralObject = validatePeripheral(operation.peripheral, for: operation.continuation) else {
            return false
        }
        guard peripheralObject.canSendWriteWithoutResponse == false else {
            operation.continuation.resume()
            return false
        }
        // wait until delegate is called
        return true
    }
    
    func execute(_ operation: Operation.NotificationState) -> Bool {
        log?("Peripheral \(operation.characteristic.peripheral) will \(operation.isEnabled ? "enable" : "disable") notifications for characteristic \(operation.characteristic.uuid)")
        // check power on
        guard validateState(.poweredOn, for: operation.continuation) else {
            return false
        }
        // get peripheral
        guard let peripheralObject = validatePeripheral(operation.characteristic.peripheral, for: operation.continuation) else {
            return false
        }
        // check connected
        guard validateConnected(peripheralObject, for: operation.continuation) else {
            return false
        }
        // get characteristic
        guard let characteristicObject = validateCharacteristic(operation.characteristic, for: operation.continuation) else {
            return false
        }
        // notify
        peripheralObject.setNotifyValue(operation.isEnabled, for: characteristicObject)
        return true
    }
    
    func execute(_ operation: Operation.ReadRSSI) -> Bool {
        self.log?("Will read RSSI for \(operation.peripheral)")
        // check power on
        guard validateState(.poweredOn, for: operation.continuation) else {
            return false
        }
        // get peripheral
        guard let peripheralObject = validatePeripheral(operation.peripheral, for: operation.continuation) else {
            return false
        }
        // check connected
        guard validateConnected(peripheralObject, for: operation.continuation) else {
            return false
        }
        // read value
        peripheralObject.readRSSI()
        return true
    }
    
    func execute(_ operation: Operation.Scan) {
        log?("Will scan for nearby devices")
        let serviceUUIDs: [CBUUID]? = operation.services.isEmpty ? nil : operation.services.map { CBUUID($0) }
        let options: [String: Any] = [
            CBCentralManagerScanOptionAllowDuplicatesKey: NSNumber(value: operation.filterDuplicates == false)
        ]
        // reset cache
        self.cache = Cache()
        // start scanning
        //self.continuation.isScanning.yield(true)
        self.centralManager.scanForPeripherals(withServices: serviceUUIDs, options: options)
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
    
    func validateDescriptor<T>(
        _ descriptor: Descriptor,
        for continuation: PeripheralContinuation<T, Error>
    ) -> CBDescriptor? {
        guard let descriptorObject = self.cache.descriptors[descriptor] else {
            continuation.resume(throwing: CentralError.invalidAttribute(descriptor.uuid))
            return nil
        }
        return descriptorObject
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
            self.central.log?(message)
        }
        
        // MARK: - CBCentralManagerDelegate
        
        @objc(centralManagerDidUpdateState:)
        func centralManagerDidUpdateState(_ centralManager: CBCentralManager) {
            assert(self.central != nil)
            assert(self.central?.centralManager === centralManager)
            let state = unsafeBitCast(centralManager.state, to: DarwinBluetoothState.self)
            log("Did update state \(state)")
            //self.central.continuation.state?.yield(state)
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
            guard let operation = self.central.continuation.scan.current else {
                assertionFailure("Not currently scanning")
                return
            }
            operation.continuation.yield(scanResult)
        }
        
        #if os(iOS)
        func centralManager(
            _ central: CBCentralManager,
            connectionEventDidOccur event: CBConnectionEvent,
            for corePeripheral: CBPeripheral
        ) {
            log("\(corePeripheral.id.uuidString) connection event")
        }
        #endif
        
        @objc(centralManager:didConnectPeripheral:)
        func centralManager(
            _ centralManager: CBCentralManager,
            didConnect corePeripheral: CBPeripheral
        ) {
            log("Did connect to peripheral \(corePeripheral.id.uuidString)")
            assert(corePeripheral.state != .disconnected, "Should be connected")
            assert(self.central != nil)
            assert(self.central?.centralManager === centralManager)
            let peripheral = Peripheral(corePeripheral)
            self.central.dequeue(for: peripheral) {
                guard case let .connect(operation) = $0 else {
                    assertionFailure("Invalid continuation")
                    return
                }
                operation.continuation.resume()
            }
        }
        
        @objc(centralManager:didFailToConnectPeripheral:error:)
        func centralManager(
            _ centralManager: CBCentralManager,
            didFailToConnect corePeripheral: CBPeripheral,
            error: Swift.Error?
        ) {
            log("Did fail to connect to peripheral \(corePeripheral.id.uuidString) (\(error!))")
            assert(self.central != nil)
            assert(self.central?.centralManager === centralManager)
            assert(corePeripheral.state != .connected)
            let peripheral = Peripheral(corePeripheral)
            self.central.dequeue(for: peripheral) {
                guard case let .connect(operation) = $0 else {
                    assertionFailure("Invalid continuation")
                    return
                }
                operation.continuation.resume(throwing: error ?? CentralError.disconnected)
            }
        }
        
        @objc(centralManager:didDisconnectPeripheral:error:)
        func centralManager(
            _ central: CBCentralManager,
            didDisconnectPeripheral corePeripheral: CBPeripheral,
            error: Swift.Error?
        ) {
            if let error = error {
                log("Did disconnect peripheral \(corePeripheral.id.uuidString) due to error \(error.localizedDescription)")
            } else {
                log("Did disconnect peripheral \(corePeripheral.id.uuidString)")
            }
            
            let peripheral = Peripheral(corePeripheral)
            //self.central.continuation.didDisconnect.yield(peripheral)
            
            // TODO: Use error from CoreBluetooth
            let disconnectionError = CentralError.disconnected
            guard let context = self.central.continuation.peripherals[peripheral] else {
                assertionFailure("Missing context")
                return
            }
            // cancel current action that requires an active connection
            if let _ = context.queue.current {
                context.queue.pop { operation in
                    operation.resume(throwing: disconnectionError)
                }
            }
            // stop notifications
            context.notificationStream.forEach {
                $0.value.finish(throwing: disconnectionError)
            }
            context.notificationStream.removeAll()
        }
        
        // MARK: - CBPeripheralDelegate
        
        @objc(peripheral:didDiscoverServices:)
        func peripheral(
            _ corePeripheral: CBPeripheral,
            didDiscoverServices error: Swift.Error?
        ) {
            
            if let error = error {
                log("Peripheral \(corePeripheral.id.uuidString) failed discovering services (\(error))")
            } else {
                log("Peripheral \(corePeripheral.id.uuidString) did discover \(corePeripheral.services?.count ?? 0) services")
            }
            
            let peripheral = Peripheral(corePeripheral)
            self.central.dequeue(for: peripheral) {
                guard case let .discoverServices(operation) = $0 else {
                    assertionFailure("Invalid continuation")
                    return
                }
                if let error = error {
                    operation.continuation.resume(throwing: error)
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
                    operation.continuation.resume(returning: services)
                }
            }
        }
        
        @objc(peripheral:didDiscoverCharacteristicsForService:error:)
        func peripheral(
            _ peripheralObject: CBPeripheral,
            didDiscoverCharacteristicsFor serviceObject: CBService,
            error: Error?
        ) {
            
            if let error = error {
                log("Peripheral \(peripheralObject.id.uuidString) failed discovering characteristics (\(error))")
            } else {
                log("Peripheral \(peripheralObject.id.uuidString) did discover \(serviceObject.characteristics?.count ?? 0) characteristics for service \(serviceObject.uuid.uuidString)")
            }
            
            let service = Service(
                service: serviceObject,
                peripheral: peripheralObject
            )
            self.central.dequeue(for: service.peripheral) {
                guard case let .discoverCharacteristics(operation) = $0 else {
                    assertionFailure("Invalid continuation")
                    return
                }
                if let error = error {
                    operation.continuation.resume(throwing: error)
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
                    operation.continuation.resume(returning: characteristics)
                }
            }
        }
        
        @objc(peripheral:didUpdateValueForCharacteristic:error:)
        func peripheral(
            _ peripheralObject: CBPeripheral,
            didUpdateValueFor characteristicObject: CBCharacteristic,
            error: Error?
        ) {
            
            if let error = error {
                log("Peripheral \(peripheralObject.id.uuidString) failed reading characteristic (\(error))")
            } else {
                log("Peripheral \(peripheralObject.id.uuidString) did update value for characteristic \(characteristicObject.uuid.uuidString)")
            }
            
            let characteristic = Characteristic(
                characteristic: characteristicObject,
                peripheral: peripheralObject
            )
            let data = characteristicObject.value ?? Data()
            guard let context = self.central.continuation.peripherals[characteristic.peripheral] else {
                assertionFailure("Missing context")
                return
            }
            // either read operation or notification
            if case let .readCharacteristic(operation) = context.queue.current {
                context.queue.pop { _ in
                    if let error = error {
                        operation.continuation.resume(throwing: error)
                    } else {
                        operation.continuation.resume(returning: data)
                    }
                }
            } else if characteristicObject.isNotifying {
                guard let stream = context.notificationStream[characteristic.id] else {
                    assertionFailure("Missing notification stream")
                    return
                }
                assert(error == nil, "Notifications should never fail")
                stream.yield(data)
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
                log("Peripheral \(peripheralObject.id.uuidString) failed writing characteristic (\(error))")
            } else {
                log("Peripheral \(peripheralObject.id.uuidString) did write value for characteristic \(characteristicObject.uuid.uuidString)")
            }
            let characteristic = Characteristic(
                characteristic: characteristicObject,
                peripheral: peripheralObject
            )
            // should only be called for write with response
            self.central.dequeue(for: characteristic.peripheral) {
                guard case let .writeCharacteristic(operation) = $0 else {
                    assertionFailure("Invalid continuation")
                    return
                }
                assert(operation.withResponse)
                if let error = error {
                    operation.continuation.resume(throwing: error)
                } else {
                    operation.continuation.resume()
                }
            }
        }
        
        @objc
        func peripheral(
            _ peripheralObject: CBPeripheral,
            didUpdateNotificationStateFor characteristicObject: CBCharacteristic,
            error: Swift.Error?
        ) {
            if let error = error {
                log("Peripheral \(peripheralObject.id.uuidString) failed setting notifications for characteristic (\(error))")
            } else {
                log("Peripheral \(peripheralObject.id.uuidString) did update notification state for characteristic \(characteristicObject.uuid.uuidString)")
            }
            
            let characteristic = Characteristic(
                characteristic: characteristicObject,
                peripheral: peripheralObject
            )
            self.central.dequeue(for: characteristic.peripheral) {
                guard case let .setNotification(operation) = $0 else {
                    assertionFailure("Invalid continuation")
                    return
                }
                if let error = error {
                    operation.continuation.resume(throwing: error)
                } else {
                    assert(characteristicObject.isNotifying == operation.isEnabled)
                    operation.continuation.resume()
                }
            }
        }
        
        func peripheralIsReady(toSendWriteWithoutResponse peripheralObject: CBPeripheral) {
            
            log("Peripheral \(peripheralObject.id.uuidString) is ready to send write without response")
            let peripheral = Peripheral(peripheralObject)
            guard let context = self.central.continuation.peripherals[peripheral] else {
                assertionFailure("Missing context")
                return
            }
            // possible nothing is waiting
            guard case let .isReadyToWriteWithoutResponse(operation) = context.queue.current else {
                return
            }
            self.central.dequeue(for: peripheral) { _ in
                operation.continuation.resume()
            }
        }
        
        func peripheralDidUpdateName(_ peripheralObject: CBPeripheral) {
            log("Peripheral \(peripheralObject.id.uuidString) updated name \(peripheralObject.name ?? "")")
        }
        
        func peripheral(_ peripheralObject: CBPeripheral, didReadRSSI rssiObject: NSNumber, error: Error?) {
            if let error = error {
                log("Peripheral \(peripheralObject.id.uuidString) failed to read RSSI (\(error))")
            } else {
                log("Peripheral \(peripheralObject.id.uuidString) did read RSSI \(rssiObject.description)")
            }
            let peripheral = Peripheral(peripheralObject)
            self.central.dequeueReadRSSI(for: peripheral) { operation in
                if let error = error {
                    operation.continuation.resume(throwing: error)
                } else {
                    guard let rssi = Bluetooth.RSSI(rawValue: rssiObject.int8Value) else {
                        assertionFailure("Invalid RSSI \(rssiObject)")
                        operation.continuation.resume(returning: RSSI(rawValue: -127)!)
                        return
                    }
                    operation.continuation.resume(returning: rssi)
                }
            }
        }
        
        func peripheral(
            _ peripheralObject: CBPeripheral,
            didDiscoverIncludedServicesFor serviceObject: CBService,
            error: Error?
        ) {
            if let error = error {
                log("Peripheral \(peripheralObject.id.uuidString) failed discovering included services for service \(serviceObject.uuid.description) (\(error))")
            } else {
                log("Peripheral \(peripheralObject.id.uuidString) did discover \(serviceObject.includedServices?.count ?? 0) included services for service \(serviceObject.uuid.uuidString)")
            }
                        
            let service = Service(
                service: serviceObject,
                peripheral: peripheralObject
            )
            self.central.dequeue(for: service.peripheral) {
                guard case let .discoverIncludedServices(operation) = $0 else {
                    assertionFailure("Invalid continuation")
                    return
                }
                if let error = error {
                    operation.continuation.resume(throwing: error)
                } else {
                    let serviceObjects = (serviceObject.includedServices ?? [])
                    let services = serviceObjects.map { serviceObject in
                        Service(
                            service: serviceObject,
                            peripheral: peripheralObject
                        )
                    }
                    for (index, service) in services.enumerated() {
                        self.central.cache.services[service] = serviceObjects[index]
                    }
                    operation.continuation.resume(returning: services)
                }
            }
        }
        
        @objc
        func peripheral(_ peripheralObject: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
            log("Peripheral \(peripheralObject.id.uuidString) did modify \(invalidatedServices.count) services")
            // TODO: Try to rediscover services
        }
        
        @objc
        func peripheral(
            _ peripheralObject: CBPeripheral,
            didDiscoverDescriptorsFor characteristicObject: CBCharacteristic,
            error: Error?
        ) {
            if let error = error {
                log("Peripheral \(peripheralObject.id.uuidString) failed discovering descriptors for characteristic \(characteristicObject.uuid.uuidString) (\(error))")
            } else {
                log("Peripheral \(peripheralObject.id.uuidString) did discover \(characteristicObject.descriptors?.count ?? 0) descriptors for characteristic \(characteristicObject.uuid.uuidString)")
            }
            
            let peripheral = Peripheral(peripheralObject)
            self.central.dequeue(for: peripheral) {
                guard case let .discoverDescriptors(operation) = $0 else {
                    assertionFailure("Invalid continuation")
                    return
                }
                if let error = error {
                    operation.continuation.resume(throwing: error)
                } else {
                    let descriptorObjects = (characteristicObject.descriptors ?? [])
                    let descriptors = descriptorObjects.map { descriptorObject in
                        Descriptor(
                            descriptor: descriptorObject,
                            peripheral: peripheralObject
                        )
                    }
                    // store objects in cache
                    for (index, descriptor) in descriptors.enumerated() {
                        self.central.cache.descriptors[descriptor] = descriptorObjects[index]
                    }
                    // resume
                    operation.continuation.resume(returning: descriptors)
                }
            }
        }
        
        func peripheral(
            _ peripheralObject: CBPeripheral,
            didWriteValueFor descriptorObject: CBDescriptor,
            error: Error?
        ) {
            if let error = error {
                log("Peripheral \(peripheralObject.id.uuidString) failed writing descriptor \(descriptorObject.uuid.uuidString) (\(error))")
            } else {
                log("Peripheral \(peripheralObject.id.uuidString) did write value for descriptor \(descriptorObject.uuid.uuidString)")
            }
            
            let descriptor = Descriptor(
                descriptor: descriptorObject,
                peripheral: peripheralObject
            )
            self.central.dequeue(for: descriptor.peripheral) {
                guard case let .writeDescriptor(operation) = $0 else {
                    assertionFailure("Invalid continuation")
                    return
                }
                if let error = error {
                    operation.continuation.resume(throwing: error)
                } else {
                    operation.continuation.resume()
                }
            }
        }
        
        func peripheral(
            _ peripheralObject: CBPeripheral,
            didUpdateValueFor descriptorObject: CBDescriptor,
            error: Error?
        ) {
            if let error = error {
                log("Peripheral \(peripheralObject.id.uuidString) failed updating value for descriptor \(descriptorObject.uuid.uuidString) (\(error))")
            } else {
                log("Peripheral \(peripheralObject.id.uuidString) did update value for descriptor \(descriptorObject.uuid.uuidString)")
            }
            
            let descriptor = Descriptor(
                descriptor: descriptorObject,
                peripheral: peripheralObject
            )
            self.central.dequeue(for: descriptor.peripheral) {
                guard case let .readDescriptor(operation) = $0 else {
                    assertionFailure("Invalid continuation")
                    return
                }
                if let error = error {
                    operation.continuation.resume(throwing: error)
                } else {
                    let data: Data
                    if let descriptor = DarwinDescriptor(descriptorObject) {
                        data = descriptor.data
                    } else if let dataObject = descriptorObject.value as? NSData {
                        data = dataObject as Data
                    } else {
                        data = Data()
                    }
                    operation.continuation.resume(returning: data)
                }
            }
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
#endif
