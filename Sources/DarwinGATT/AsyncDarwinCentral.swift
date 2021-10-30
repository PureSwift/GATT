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

@available(macOS 12, iOS 15.0, *)
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
    
    internal fileprivate(set) var continuation = Continuation()
    
    // MARK: - Initialization
    
    /// Initialize with the specified options.
    ///
    /// - Parameter options: An optional dictionary containing initialization options for a central manager.
    /// For available options, see [Central Manager Initialization Options](apple-reference-documentation://ts1667590).
    public init(options: Options = Options()) {
        self.log = AsyncStream(String.self, bufferingPolicy: .bufferingNewest(10)) { [unowned self] in
            continuation.log = $0
        }
        self.isScanning = AsyncStream(Bool.self, bufferingPolicy: .bufferingNewest(1)) { [unowned self] in
            continuation.isScanning = $0
        }
        self.didDisconnect = AsyncStream(Peripheral.self, bufferingPolicy: .bufferingNewest(1)) { [unowned self] in
            continuation.didDisconnect = $0
        }
        self.state = AsyncStream(DarwinBluetoothState.self, bufferingPolicy: .bufferingNewest(1)) { [unowned self] in
            continuation.state = $0
        }
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
        _ services: [BluetoothUUID] = [],
        for peripheral: Peripheral
    ) -> AsyncThrowingStream<Service<Peripheral, AttributeID>, Error> {
        let coreServices = services.isEmpty ? nil : services.map { CBUUID($0) }
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
                peripheralObject.discoverServices(coreServices)
            }
        }
    }
    
    public func discoverCharacteristics(
        _ characteristics: [BluetoothUUID],
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
                // discover
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
        // wait until continuation is called
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
    
    public func notify(
        for characteristic: Characteristic<Peripheral, AttributeID>
    ) -> AsyncThrowingStream<Data, Error> {
        
    }
    
    public func maximumTransmissionUnit(for peripheral: Peripheral) async throws -> MaximumTransmissionUnit {
        
    }
    
    private func log(_ message: String) {
        continuation.log.yield(message)
    }
}

// MARK: - Supporting Types

@available(macOS 12, iOS 15.0, *)
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

@available(macOS 12, iOS 15.0, *)
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
        var discoverCharacteristics = [Peripheral: AsyncThrowingStream<Characteristic<Peripheral, AttributeID>, Error>.Continuation]()
        var readCharacteristic = [Characteristic<Peripheral, AttributeID>: CheckedContinuation<Data, Error>]()
        var writeCharacteristic = [Characteristic<Peripheral, AttributeID>: CheckedContinuation<(), Error>]()
        var isReadyToWriteWithoutResponse = [Peripheral: CheckedContinuation<(), Error>]()
    }
}

@available(macOS 12, iOS 15.0, *)
internal extension AsyncDarwinCentral {
    
    @objc(GATTAsyncCentralManagerDelegate)
    final class Delegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
        
        private(set) weak var central: AsyncDarwinCentral!
        
        fileprivate init(_ central: AsyncDarwinCentral) {
            super.init()
            self.central = central
        }
        
        // MARK: - CBCentralManagerDelegate
        
        func centralManagerDidUpdateState(_ centralManager: CBCentralManager) {
            assert(self.central != nil)
            assert(self.central?.centralManager === centralManager)
            let state = unsafeBitCast(centralManager.state, to: DarwinBluetoothState.self)
            self.central.log("Did update state \(state)")
            self.central.continuation.state.yield(state)
        }
        
        func centralManager(_ centralManager: CBCentralManager, willRestoreState state: [String : Any]) {
            assert(self.central != nil)
            assert(self.central?.centralManager === centralManager)
            self.central.log("Will restore state \(NSDictionary(dictionary: state).description)")
            // An array of peripherals for use when restoring the state of a central manager.
            if let peripherals = state[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
                for peripheral in peripherals {
                    self.central.cache.peripherals[Peripheral(peripheral)] = peripheral
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
        
        func centralManager(
            _ central: CBCentralManager,
            connectionEventDidOccur event: CBConnectionEvent,
            for corePeripheral: CBPeripheral
        ) {
            self.central.log("Connect event \(event.rawValue) for \(corePeripheral.gattIdentifier.uuidString)")
        }
        
        func centralManager(
            _ centralManager: CBCentralManager,
            didConnect corePeripheral: CBPeripheral
        ) {
            self.central.log("Did connect to peripheral \(corePeripheral.gattIdentifier.uuidString)")
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
            self.central.log("Did fail to connect to peripheral \(corePeripheral.gattIdentifier.uuidString) (\(error!))")
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
                        
            if let error = error {
                self.central.log("Did disconnect peripheral \(corePeripheral.gattIdentifier.uuidString) due to error \(error.localizedDescription)")
            } else {
                self.central.log("Did disconnect peripheral \(corePeripheral.gattIdentifier.uuidString)")
            }
            
            let peripheral = Peripheral(corePeripheral)
            self.central.didDisconnect?(peripheral)
            
            // cancel all actions that require an active connection
            self.discoverServices[peripheral]?
                .didComplete(.failure(CentralError.disconnected))
            self.discoverCharacteristics[peripheral]?
                .didComplete(.failure(CentralError.disconnected))
            self.readCharacteristicValue[peripheral]?
                .didComplete(.failure(CentralError.disconnected))
            self.writeCharacteristicValue[peripheral]?
                .didComplete(.failure(CentralError.disconnected))
            self.flushWriteWithoutResponse[peripheral]?
                .didComplete(.failure(CentralError.disconnected))
            self.setNotification[peripheral]?
                .didComplete(.failure(CentralError.disconnected))
            self.notifications[peripheral] = nil
        }
        
        // MARK: - CBPeripheralDelegate
        
        func peripheral(_ corePeripheral: CBPeripheral, didDiscoverServices error: Error?) {
            
            if let error = error {
                log?("Error discovering services (\(error))")
            } else {
                log?("Peripheral \(corePeripheral.gattIdentifier.uuidString) did discover \(corePeripheral.services?.count ?? 0) services")
            }
            
            let peripheral = Peripheral(corePeripheral)
            guard let callback = self.discoverServices[peripheral]
                else { assertionFailure("Missing callback"); return }
            
            if let error = error {
                callback.didComplete(.failure(error))
            } else {
                let services = (corePeripheral.services ?? []).map {
                    Service(id: ObjectIdentifier($0),
                            uuid: BluetoothUUID($0.uuid),
                            peripheral: peripheral,
                            isPrimary: $0.isPrimary)
                }
                callback.didComplete(.success(services))
            }
            
            // remove callback
            self.discoverServices[peripheral] = nil
        }
        
        func peripheral(_ corePeripheral: CBPeripheral, didDiscoverCharacteristicsFor coreService: CBService, error: Error?) {
            
            if let error = error {
                log?("Error discovering characteristics (\(error))")
                
            } else {
                log?("Peripheral \(corePeripheral.gattIdentifier.uuidString) did discover \(coreService.characteristics?.count ?? 0) characteristics for service \(coreService.uuid.uuidString)")
            }
            
            let peripheral = Peripheral(corePeripheral)
            guard let callback = self.discoverCharacteristics[peripheral]
                else { assertionFailure("Missing callback"); return }
            
            if let error = error {
                callback.didComplete(.failure(error))
            } else {
                let characteristics = (coreService.characteristics ?? []).map {
                    Characteristic(id: ObjectIdentifier($0),
                                   uuid: BluetoothUUID($0.uuid),
                                   peripheral: peripheral,
                                   properties: .init(rawValue: numericCast($0.properties.rawValue)))
                }
                callback.didComplete(.success(characteristics))
            }
            
            // remove callback
            self.discoverCharacteristics[peripheral] = nil
        }
        
        func peripheral(_ corePeripheral: CBPeripheral, didUpdateValueFor coreCharacteristic: CBCharacteristic, error: Error?) {
            
            let data = coreCharacteristic.value ?? Data()
            
            if let error = error {
                log?("Error reading characteristic (\(error))")
            } else {
                log?("Peripheral \(corePeripheral.gattIdentifier.uuidString) did update value for characteristic \(coreCharacteristic.uuid.uuidString)")
            }
            
            let peripheral = Peripheral(corePeripheral)
            
            // write with response
            if let completion = self.readCharacteristicValue[peripheral] {
                if let error = error {
                    completion.didComplete(.failure(error))
                } else {
                    completion.didComplete(.success(data))
                }
                self.readCharacteristicValue[peripheral] = nil
            } else if let notification = self.notifications[peripheral] {
                assert(error == nil, "Notifications should never fail")
                notification(data)
                self.notifications[peripheral] = nil
            }
        }
        
        func peripheral(_ corePeripheral: CBPeripheral, didWriteValueFor coreCharacteristic: CBCharacteristic, error: Swift.Error?) {
            
            if let error = error {
                log?("Error writing characteristic (\(error))")
            } else {
                log?("Peripheral \(corePeripheral.gattIdentifier.uuidString) did write value for characteristic \(coreCharacteristic.uuid.uuidString)")
            }
            
            let peripheral = Peripheral(corePeripheral)
            guard let callback = self.writeCharacteristicValue[peripheral]
                else { assertionFailure("Missing callback"); return }
            
            if let error = error {
                callback.didComplete(.failure(error))
            } else {
                callback.didComplete(.success(()))
            }
            
            // remove callback
            self.writeCharacteristicValue[peripheral] = nil
        }
        
        func peripheral(_ corePeripheral: CBPeripheral,
                           didUpdateNotificationStateFor coreCharacteristic: CBCharacteristic,
                           error: Swift.Error?) {
            
            if let error = error {
                log?("Error setting notifications for characteristic (\(error))")
            } else {
                log?("Peripheral \(corePeripheral.gattIdentifier.uuidString) did update notification state for characteristic \(coreCharacteristic.uuid.uuidString)")
            }
            
            let peripheral = Peripheral(corePeripheral)
            guard let callback = self.setNotification[peripheral]
                else { assertionFailure("Missing callback"); return }
            
            if let error = error {
                callback.didComplete(.failure(error))
            } else {
                callback.didComplete(.success(()))
            }
            
            // remove callback
            self.setNotification[peripheral] = nil
        }
        
        func peripheral(_ peripheral: CBPeripheral,
                        didUpdateValueFor descriptor: CBDescriptor,
                        error: Swift.Error?) {
            
            
        }
        
        func peripheralIsReady(toSendWriteWithoutResponse corePeripheral: CBPeripheral) {
            self.central.log("Peripheral \(corePeripheral.gattIdentifier.uuidString) is ready to send write without response")
            let peripheral = Peripheral(corePeripheral)
            if let continuation = self.central.continuation.isReadyToWriteWithoutResponse[peripheral] {
                continuation.resume()
                self.central.continuation.isReadyToWriteWithoutResponse[peripheral] = nil
            }
        }
    }
}

#endif
