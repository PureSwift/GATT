//
//  AsyncDarwinCentral.swift
//  
//
//  Created by Alsey Coleman Miller on 11/10/21.
//

#if swift(>=5.5) && canImport(CoreBluetooth)
import Foundation
import Dispatch
import CoreBluetooth
import Bluetooth
import GATT

@available(macOS 12, iOS 15.0, watchOS 8.0, tvOS 15, *)
public final class AsyncDarwinCentral { //: AsyncCentral {
    
    // MARK: - Properties
    
    public let options: Options
    
    public let state: AsyncStream<DarwinBluetoothState>
    
    public let log: AsyncStream<String>
    
    public let isScanning: AsyncStream<Bool>
    
    public let didDisconnect: AsyncStream<Peripheral>
    
    private var centralManager: CBCentralManager!
    
    private var delegate: Delegate!
    
    fileprivate let queue = DispatchQueue(label: "AsyncDarwinCentral Queue")
    
    internal fileprivate(set) var cache = Cache()
    
    internal fileprivate(set) var continuation: Continuation
    
    // MARK: - Initialization
    
    /// Initialize with the specified options.
    ///
    /// - Parameter options: An optional dictionary containing initialization options for a central manager.
    /// For available options, see [Central Manager Initialization Options](apple-reference-documentation://ts1667590).
    public init(options: Options = Options()) {
        self.options = options
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
        self.continuation = continuation
        self.delegate = Delegate(self)
        self.centralManager = CBCentralManager(
            delegate: self.delegate,
            queue: self.queue,
            options: options.optionsDictionary
        )
    }
    
    // MARK: - Methods
    
    /// Scans for peripherals that are advertising services.
    public func scan(
        filterDuplicates: Bool = true
    ) -> AsyncThrowingStream<ScanData<Peripheral, Advertisement>, Error> {
        return scan(with: [], filterDuplicates: filterDuplicates)
    }
    
    /// Scans for peripherals that are advertising services.
    public func scan(
        with services: Set<BluetoothUUID>,
        filterDuplicates: Bool
    ) -> AsyncThrowingStream<ScanData<Peripheral, Advertisement>, Error> {
        let serviceUUIDs: [CBUUID]? = services.isEmpty ? nil : services.map { CBUUID($0) }
        let options: [String: Any] = [
            CBCentralManagerScanOptionAllowDuplicatesKey: NSNumber(value: filterDuplicates == false)
        ]
        return AsyncThrowingStream(ScanData<Peripheral, Advertisement>.self, bufferingPolicy: .bufferingNewest(100)) {  [weak self] continuation in
            guard let self = self else { return }
            self.queue.async {
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
                self.centralManager.scanForPeripherals(withServices: serviceUUIDs, options: options)
            }
        }
    }
    
    public func stopScan() async {
        await withCheckedContinuation { [weak self] (continuation: CheckedContinuation<(), Never>) in
            guard let self = self else { return }
            self.queue.async {
                guard let scanContinuation = self.continuation.scan else {
                    continuation.resume() // not currently scanning
                    return
                }
                self.centralManager.stopScan()
                self.log("Discovered \(self.cache.peripherals.count) peripherals")
                scanContinuation.finish(throwing: nil) // end stream
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
        try await withCheckedThrowingContinuation { [weak self] (continuation: CheckedContinuation<(), Error>) in
            guard let self = self else { return }
            self.queue.async {
                // cancel old task
                self.continuation.connect[peripheral]?.resume(throwing: CancellationError())
                self.continuation.connect[peripheral] = nil
                // check power on
                let state = self.centralManager._state
                guard state == .poweredOn else {
                    continuation.resume(throwing: DarwinCentralError.invalidState(state))
                    return
                }
                // get CoreBluetooth objects from cache
                guard let peripheralObject = self.cache.peripherals[peripheral] else {
                    continuation.resume(throwing: CentralError.unknownPeripheral)
                    return
                }
                
                // connect
                self.continuation.connect[peripheral] = continuation
                self.centralManager.connect(peripheralObject, options: options)
            }
        }
    }
    
    public func disconnect(_ peripheral: Peripheral) {
        self.queue.async { [weak self] in
            guard let self = self else { return }
            // get CoreBluetooth objects from cache
            guard let peripheralObject = self.cache.peripherals[peripheral] else {
                return
            }
            self.centralManager.cancelPeripheralConnection(peripheralObject)
        }
    }
    
    public func disconnectAll() {
        self.queue.async { [weak self] in
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
    ) -> AsyncThrowingStream<Service<Peripheral, AttributeID>, Error> {
        let serviceUUIDs = services.isEmpty ? nil : services.map { CBUUID($0) }
        return AsyncThrowingStream(Service<Peripheral, AttributeID>.self, bufferingPolicy: .unbounded) { [weak self] continuation in
            guard let self = self else { return }
            self.queue.async {
                // get peripheral
                guard let peripheralObject = self.cache.peripherals[peripheral] else {
                    continuation.finish(throwing: CentralError.unknownPeripheral)
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
                // cancel old task
                if let oldTask = self.continuation.discoverServices[peripheral] {
                    oldTask.finish(throwing: CancellationError())
                    self.continuation.discoverServices[peripheral] = nil
                }
                // discover
                self.continuation.discoverServices[peripheral] = continuation
                peripheralObject.discoverServices(serviceUUIDs)
            }
        }
    }
    
    public func discoverIncludedServices(
        _ services: Set<BluetoothUUID> = [],
        for service: Service<Peripheral, AttributeID>
    ) -> AsyncThrowingStream<Service<Peripheral, AttributeID>, Error> {
        let serviceUUIDs = services.isEmpty ? nil : services.map { CBUUID($0) }
        return AsyncThrowingStream(Service<Peripheral, AttributeID>.self, bufferingPolicy: .unbounded) { [weak self] continuation in
            guard let self = self else { return }
            self.queue.async {
                let peripheral = service.peripheral
                // get peripheral
                guard let peripheralObject = self.cache.peripherals[peripheral] else {
                    continuation.finish(throwing: CentralError.unknownPeripheral)
                    return
                }
                // get service
                guard let serviceObject = self.cache.services[service] else {
                    continuation.finish(throwing: CentralError.invalidAttribute(service.uuid))
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
                // cancel old task
                if let oldTask = self.continuation.discoverIncludedServices[service] {
                    oldTask.finish(throwing: CancellationError())
                    self.continuation.discoverIncludedServices[service] = nil
                }
                // discover
                self.continuation.discoverIncludedServices[service] = continuation
                peripheralObject.discoverIncludedServices(serviceUUIDs, for: serviceObject)
            }
        }
    }
    
    public func discoverCharacteristics(
        _ characteristics: Set<BluetoothUUID>,
        for service: Service<Peripheral, AttributeID>
    ) -> AsyncThrowingStream<Characteristic<Peripheral, AttributeID>, Error> {
        let characteristicUUIDs = characteristics.isEmpty ? nil : characteristics.map { CBUUID($0) }
        return AsyncThrowingStream(Characteristic<Peripheral, AttributeID>.self, bufferingPolicy: .unbounded) { [weak self] continuation in
            guard let self = self else { return }
            self.queue.async {
                let peripheral = service.peripheral
                // get peripheral
                guard let peripheralObject = self.cache.peripherals[peripheral] else {
                    continuation.finish(throwing: CentralError.unknownPeripheral)
                    return
                }
                // get service
                guard let serviceObject = self.cache.services[service] else {
                    continuation.finish(throwing: CentralError.invalidAttribute(service.uuid))
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
                // cancel old task
                if let oldTask = self.continuation.discoverCharacteristics[peripheral] {
                    oldTask.finish(throwing: CancellationError())
                    self.continuation.discoverCharacteristics[peripheral] = nil
                }
                // discover
                self.continuation.discoverCharacteristics[peripheral] = continuation
                peripheralObject.discoverCharacteristics(characteristicUUIDs, for: serviceObject)
            }
        }
    }
    
    public func readValue(
        for characteristic: Characteristic<Peripheral, AttributeID>
    ) async throws -> Data {
        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self = self else { return }
            self.queue.async {
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
                // cancel old task
                if let oldTask = self.continuation.readCharacteristic[characteristic] {
                    oldTask.resume(throwing: CancellationError())
                    self.continuation.readCharacteristic[characteristic] = nil
                }
                // read value
                self.continuation.readCharacteristic[characteristic] = continuation
                peripheralObject.readValue(for: characteristicObject)
            }
        }
    }
    
    public func writeValue(
        _ data: Data,
        for characteristic: Characteristic<Peripheral, AttributeID>,
        withResponse: Bool = true
    ) async throws {
        if withResponse {
            try await write(data, type: .withResponse, for: characteristic)
        } else {
            try await waitUntilCanSendWriteWithoutResponse(for: characteristic.peripheral)
            try await write(data, type: .withoutResponse, for: characteristic)
        }
    }
    
    public func notify(
        for characteristic: Characteristic<Peripheral, AttributeID>
    ) -> AsyncThrowingStream<Data, Error> {
        return AsyncThrowingStream(Data.self, bufferingPolicy: .bufferingNewest(100)) { [weak self] continuation in
            guard let self = self else { return }
            self.queue.async {
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
                // cancel old task
                if let oldTask = self.continuation.discoverCharacteristics[peripheral] {
                    oldTask.finish(throwing: CancellationError())
                    self.continuation.discoverCharacteristics[peripheral] = nil
                }
                // notify
                self.continuation.notificationStream[characteristic] = continuation
                peripheralObject.setNotifyValue(true, for: characteristicObject)
            }
        }
    }
    
    public func stopNotifications(
        for characteristic: Characteristic<Peripheral, AttributeID>
    ) async throws {
        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self = self else { return }
            self.queue.async {
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
                // cancel old task
                if let oldTask = self.continuation.discoverCharacteristics[peripheral] {
                    oldTask.finish(throwing: CancellationError())
                    self.continuation.discoverCharacteristics[peripheral] = nil
                }
                // notify
                self.continuation.stopNotification[characteristic] = continuation
                peripheralObject.setNotifyValue(false, for: characteristicObject)
            }
        }
    }
    
    public func maximumTransmissionUnit(for peripheral: Peripheral) async throws -> MaximumTransmissionUnit {
        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self = self else { return }
            self.queue.async {
                // get peripheral
                guard let peripheralObject = self.cache.peripherals[peripheral] else {
                    continuation.resume(throwing: CentralError.unknownPeripheral)
                    return
                }
                // get MTU
                let rawValue = peripheralObject.maximumWriteValueLength(for: .withoutResponse) + 3
                assert(peripheralObject.mtuLength.intValue == rawValue)
                guard let mtu = MaximumTransmissionUnit(rawValue: UInt16(rawValue)) else {
                    assertionFailure("Invalid MTU \(rawValue)")
                    continuation.resume(returning: .default)
                    return
                }
                continuation.resume(returning: mtu)
            }
        }
    }
    
    public func rssi(for peripheral: Peripheral) async throws -> RSSI {
        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self = self else { return }
            self.queue.async {
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
    
    private func write(
        _ data: Data,
        type: CBCharacteristicWriteType,
        for characteristic: Characteristic<Peripheral, AttributeID>
    ) async throws {
        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self = self else { return }
            self.queue.async {
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
                // cancel old task
                if let oldTask = self.continuation.writeCharacteristic[characteristic] {
                    oldTask.resume(throwing: CancellationError())
                    self.continuation.writeCharacteristic[characteristic] = nil
                }
                // store continuation for callback
                if type == .withResponse {
                    // calls `peripheral:didWriteValueForCharacteristic:error:` only
                    // if you specified the write type as `.withResponse`.
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
        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self = self else { return }
            self.queue.async {
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
        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self = self else { return }
            self.queue.async {
                // get peripheral
                guard let peripheralObject = self.cache.peripherals[peripheral] else {
                    continuation.resume(throwing: CentralError.unknownPeripheral)
                    return
                }
                if peripheralObject.canSendWriteWithoutResponse {
                    continuation.resume()
                } else {
                    // wait until delegate is called
                    self.continuation.isReadyToWriteWithoutResponse[peripheral] = continuation
                }
            }
        }
    }
}

// MARK: - Supporting Types

@available(macOS 12, iOS 15.0, watchOS 8.0, tvOS 15, *)
public extension AsyncDarwinCentral {
    
    typealias Advertisement = DarwinAdvertisementData
    
    typealias State = DarwinBluetoothState
    
    typealias AttributeID = ObjectIdentifier
    
    /// Central Peer
    ///
    /// Represents a remote central device that has connected to an app implementing the peripheral role on a local device.
    struct Peripheral: Peer {
        
        public let identifier: UUID
        
        internal init(_ peripheral: CBPeripheral) {
            self.identifier = peripheral.gattIdentifier
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

@available(macOS 12, iOS 15.0, watchOS 8.0, tvOS 15, *)
internal extension AsyncDarwinCentral {
    
    struct Cache {
        var peripherals = [Peripheral: CBPeripheral]()
        var services = [Service<Peripheral, AttributeID>: CBService]()
        var characteristics = [Characteristic<Peripheral, AttributeID>: CBCharacteristic]()
        var descriptors = [Descriptor<Peripheral, AttributeID>: CBCharacteristic]()
    }
    
    struct Continuation {
        var log: AsyncStream<String>.Continuation!
        var isScanning: AsyncStream<Bool>.Continuation!
        var didDisconnect: AsyncStream<Peripheral>.Continuation!
        var state: AsyncStream<DarwinBluetoothState>.Continuation!
        var scan: AsyncThrowingStream<ScanData<Peripheral, Advertisement>, Error>.Continuation?
        var connect = [Peripheral: CheckedContinuation<(), Error>]()
        var discoverServices = [Peripheral: AsyncThrowingStream<Service<Peripheral, AttributeID>, Error>.Continuation]()
        var discoverIncludedServices = [Service<Peripheral, AttributeID>: AsyncThrowingStream<Service<Peripheral, AttributeID>, Error>.Continuation]()
        var discoverCharacteristics = [Peripheral: AsyncThrowingStream<Characteristic<Peripheral, AttributeID>, Error>.Continuation]()
        var discoverDescriptors = [Peripheral: AsyncThrowingStream<Descriptor<Peripheral, AttributeID>, Error>.Continuation]()
        var readCharacteristic = [Characteristic<Peripheral, AttributeID>: CheckedContinuation<Data, Error>]()
        var readDescriptor = [Descriptor<Peripheral, AttributeID>: CheckedContinuation<Data, Error>]()
        var writeCharacteristic = [Characteristic<Peripheral, AttributeID>: CheckedContinuation<(), Error>]()
        var writeDescriptor = [Descriptor<Peripheral, AttributeID>: CheckedContinuation<(), Error>]()
        var isReadyToWriteWithoutResponse = [Peripheral: CheckedContinuation<(), Error>]()
        var notificationStream = [Characteristic<Peripheral, AttributeID>: AsyncThrowingStream<Data, Error>.Continuation]()
        var stopNotification = [Characteristic<Peripheral, AttributeID>: CheckedContinuation<(), Error>]()
        var readRSSI = [Peripheral: CheckedContinuation<RSSI, Error>]()
    }
}

@available(macOS 12, iOS 15.0, watchOS 8.0, tvOS 15, *)
internal extension AsyncDarwinCentral {
    
    @objc(GATTAsyncCentralManagerDelegate)
    final class Delegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
        
        private(set) weak var central: AsyncDarwinCentral!
        
        fileprivate init(_ central: AsyncDarwinCentral) {
            super.init()
            self.central = central
        }
        
        private func log(_ function: String = #function, _ arguments: String?...) {
            let message = arguments
                .lazy
                .compactMap { $0 }
                .reduce(into: function) { $0 += " " + $1 }
            self.central.log(message)
        }
        
        // MARK: - CBCentralManagerDelegate
        
        func centralManagerDidUpdateState(_ centralManager: CBCentralManager) {
            assert(self.central != nil)
            assert(self.central?.centralManager === centralManager)
            let state = unsafeBitCast(centralManager.state, to: DarwinBluetoothState.self)
            log(state.description)
            self.central.continuation.state.yield(state)
        }
        
        func centralManager(_ centralManager: CBCentralManager, willRestoreState state: [String : Any]) {
            assert(self.central != nil)
            assert(self.central?.centralManager === centralManager)
            log("\(NSDictionary(dictionary: state).description)")
            // An array of peripherals for use when restoring the state of a central manager.
            if let peripherals = state[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
                for peripheralObject in peripherals {
                    self.central.cache.peripherals[Peripheral(peripheralObject)] = peripheralObject
                }
            }
        }
        
        func centralManager(
            _ centralManager: CBCentralManager,
            didDiscover corePeripheral: CBPeripheral,
            advertisementData: [String : Any],
            rssi: NSNumber
        ) {
            assert(self.central != nil)
            assert(self.central?.centralManager === centralManager)
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
            log(event.rawValue.description, corePeripheral.gattIdentifier.uuidString)
        }
        #endif
        
        func centralManager(
            _ centralManager: CBCentralManager,
            didConnect corePeripheral: CBPeripheral
        ) {
            log(corePeripheral.gattIdentifier.uuidString)
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
        
        func centralManager(
            _ centralManager: CBCentralManager,
            didFailToConnect corePeripheral: CBPeripheral,
            error: Swift.Error?
        ) {
            log(corePeripheral.gattIdentifier.uuidString, error?.localizedDescription ?? "")
            assert(self.central != nil)
            assert(self.central?.centralManager === centralManager)
            let peripheral = Peripheral(corePeripheral)
            guard let continuation = self.central.continuation.connect[peripheral] else {
                assertionFailure("Missing continuation")
                return
            }
            continuation.resume(throwing: error ?? CentralError.disconnected)
            self.central.continuation.connect[peripheral] = nil
        }
        
        func centralManager(
            _ central: CBCentralManager,
            didDisconnectPeripheral corePeripheral: CBPeripheral,
            error: Swift.Error?
        ) {
                        
            log(corePeripheral.gattIdentifier.uuidString, error?.localizedDescription)
            
            let peripheral = Peripheral(corePeripheral)
            self.central.continuation.didDisconnect.yield(peripheral)
            
            // cancel all actions that require an active connection
            self.central.continuation.discoverServices[peripheral]?
                .finish(throwing: CentralError.disconnected)
            self.central.continuation.discoverCharacteristics[peripheral]?
                .finish(throwing: CentralError.disconnected)
            self.central.continuation.readCharacteristic
                .filter { $0.key.peripheral == peripheral }
                .forEach { $0.value.resume(throwing: CentralError.disconnected) }
            self.central.continuation.writeCharacteristic
                .filter { $0.key.peripheral == peripheral }
                .forEach { $0.value.resume(throwing: CentralError.disconnected) }
            self.central.continuation.isReadyToWriteWithoutResponse[peripheral]?
                .resume(throwing: CentralError.disconnected)
            self.central.continuation.notificationStream
                .filter { $0.key.peripheral == peripheral }
                .forEach { $0.value.finish(throwing: CentralError.disconnected) }
            self.central.continuation.stopNotification
                .filter { $0.key.peripheral == peripheral }
                .forEach { $0.value.resume(throwing: CentralError.disconnected) }
        }
        
        // MARK: - CBPeripheralDelegate
        
        func peripheral(
            _ corePeripheral: CBPeripheral,
            didDiscoverServices error: Error?
        ) {
            
            log(corePeripheral.gattIdentifier.uuidString, error?.localizedDescription)
            
            let peripheral = Peripheral(corePeripheral)
            guard let continuation = self.central.continuation.discoverServices[peripheral] else {
                assertionFailure("Missing continuation")
                return
            }
            if let error = error {
                continuation.finish(throwing: error)
            } else {
                for serviceObject in (corePeripheral.services ?? []) {
                    let service = Service(
                        service: serviceObject,
                        peripheral: corePeripheral
                    )
                    continuation.yield(service)
                }
                continuation.finish(throwing: nil)
            }
            // remove callback
            self.central.continuation.discoverServices[peripheral] = nil
        }
        
        func peripheral(
            _ peripheralObject: CBPeripheral,
            didDiscoverCharacteristicsFor serviceObject: CBService,
            error: Error?
        ) {
            
            log(peripheralObject.gattIdentifier.uuidString, serviceObject.uuid.uuidString, error?.localizedDescription)
            
            let peripheral = Peripheral(peripheralObject)
            guard let continuation = self.central.continuation.discoverCharacteristics[peripheral] else {
                assertionFailure("Missing continuation")
                return
            }
            if let error = error {
                continuation.finish(throwing: error)
            } else {
                for characteristicObject in (serviceObject.characteristics ?? []) {
                    let characteristic = Characteristic(
                        characteristic: characteristicObject,
                        peripheral: peripheralObject
                    )
                    continuation.yield(characteristic)
                }
                continuation.finish(throwing: nil)
            }
            // remove callback
            self.central.continuation.discoverCharacteristics[peripheral] = nil
        }
        
        func peripheral(
            _ peripheralObject: CBPeripheral,
            didUpdateValueFor characteristicObject: CBCharacteristic,
            error: Error?
        ) {
            
            log(peripheralObject.gattIdentifier.uuidString, characteristicObject.uuid.uuidString, error?.localizedDescription)
            
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
        
        func peripheral(
            _ peripheralObject: CBPeripheral,
            didWriteValueFor characteristicObject: CBCharacteristic,
            error: Swift.Error?
        ) {
            log(peripheralObject.gattIdentifier.uuidString, characteristicObject.uuid.uuidString, error?.localizedDescription)
            
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
        
        func peripheral(
            _ peripheralObject: CBPeripheral,
            didUpdateNotificationStateFor characteristicObject: CBCharacteristic,
            error: Swift.Error?
        ) {
            
            log(peripheralObject.gattIdentifier.uuidString, characteristicObject.uuid.uuidString, error?.localizedDescription)
            
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
            
            log(peripheralObject.gattIdentifier.uuidString)
            
            let peripheral = Peripheral(peripheralObject)
            if let continuation = self.central.continuation.isReadyToWriteWithoutResponse[peripheral] {
                continuation.resume()
                self.central.continuation.isReadyToWriteWithoutResponse[peripheral] = nil
            }
        }
        
        func peripheralDidUpdateName(_ peripheralObject: CBPeripheral) {
            log(peripheralObject.gattIdentifier.uuidString, peripheralObject.name)
        }
        
        func peripheral(_ peripheralObject: CBPeripheral, didReadRSSI rssiObject: NSNumber, error: Error?) {
            log(peripheralObject.gattIdentifier.uuidString, rssiObject.description, error?.localizedDescription)
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
            log(peripheralObject.gattIdentifier.uuidString, serviceObject.uuid.uuidString, error?.localizedDescription)
                        
            let service = Service(
                service: serviceObject,
                peripheral: peripheralObject
            )
            guard let continuation = self.central.continuation.discoverIncludedServices[service] else {
                assertionFailure("Missing continuation")
                return
            }
            if let error = error {
                continuation.finish(throwing: error)
            } else {
                for serviceObject in (serviceObject.includedServices ?? []) {
                    let service = Service(
                        service: serviceObject,
                        peripheral: peripheralObject
                    )
                    continuation.yield(service)
                }
                continuation.finish(throwing: nil)
            }
            // remove callback
            self.central.continuation.discoverIncludedServices[service] = nil
        }
        
        func peripheral(_ peripheralObject: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
            
            log(peripheralObject.gattIdentifier.uuidString, invalidatedServices.map { $0.uuid.uuidString }.description)
        }
        
        func peripheral(_ peripheralObject: CBPeripheral, didDiscoverDescriptorsFor characteristicObject: CBCharacteristic, error: Error?) {
            
            log(peripheralObject.gattIdentifier.uuidString, characteristicObject.uuid.uuidString, error?.localizedDescription)
            
            let peripheral = Peripheral(peripheralObject)
            guard let continuation = self.central.continuation.discoverDescriptors[peripheral] else {
                assertionFailure("Missing continuation")
                return
            }
            if let error = error {
                continuation.finish(throwing: error)
            } else {
                for descriptorObject in (characteristicObject.descriptors ?? []) {
                    let descriptor = Descriptor(
                        descriptor: descriptorObject,
                        peripheral: peripheralObject
                    )
                    continuation.yield(descriptor)
                }
                continuation.finish(throwing: nil)
            }
            // remove callback
            self.central.continuation.discoverDescriptors[peripheral] = nil
        }
        
        func peripheral(_ peripheralObject: CBPeripheral, didWriteValueFor descriptorObject: CBDescriptor, error: Error?) {
            
            log(peripheralObject.gattIdentifier.uuidString, descriptorObject.uuid.uuidString, error?.localizedDescription)
            
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
        
        func peripheral(_ peripheralObject: CBPeripheral, didUpdateValueFor descriptorObject: CBDescriptor, error: Error?) {
            
            log(peripheralObject.gattIdentifier.uuidString, descriptorObject.uuid.uuidString, error?.localizedDescription)
            
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

@available(macOS 12, iOS 15.0, watchOS 8.0, tvOS 15, *)
internal extension Service where ID == ObjectIdentifier, Peripheral == AsyncDarwinCentral.Peripheral {
    
    init(
        service serviceObject: CBService,
        peripheral peripheralObject: CBPeripheral
    ) {
        self.init(
            id: ObjectIdentifier(serviceObject),
            uuid: BluetoothUUID(serviceObject.uuid),
            peripheral: AsyncDarwinCentral.Peripheral(peripheralObject),
            isPrimary: serviceObject.isPrimary
        )
    }
}

@available(macOS 12, iOS 15.0, watchOS 8.0, tvOS 15, *)
internal extension Characteristic where ID == ObjectIdentifier, Peripheral == AsyncDarwinCentral.Peripheral {
    
    init(
        characteristic characteristicObject: CBCharacteristic,
        peripheral peripheralObject: CBPeripheral
    ) {
        self.init(
            id: ObjectIdentifier(characteristicObject),
            uuid: BluetoothUUID(characteristicObject.uuid),
            peripheral: AsyncDarwinCentral.Peripheral(peripheralObject),
            properties: .init(rawValue: numericCast(characteristicObject.properties.rawValue))
        )
    }
}

@available(macOS 12, iOS 15.0, watchOS 8.0, tvOS 15, *)
internal extension Descriptor where ID == ObjectIdentifier, Peripheral == AsyncDarwinCentral.Peripheral {
    
    init(
        descriptor descriptorObject: CBDescriptor,
        peripheral peripheralObject: CBPeripheral
    ) {
        self.init(
            id: ObjectIdentifier(descriptorObject),
            uuid: BluetoothUUID(descriptorObject.uuid),
            peripheral: AsyncDarwinCentral.Peripheral(peripheralObject)
        )
    }
}

#endif
