//
//  DarwinCombineCentral.swift
//  
//
//  Created by Alsey Coleman Miller on 6/6/20.
//

import Foundation
import Bluetooth
import GATT

#if canImport(CoreBluetooth)
import CoreBluetooth

/// CoreBluetooth GATT Central Manager
public final class DarwinCentral: CentralProtocol {
    
    // MARK: - Properties
    
    public var log: ((String) -> ())?
    
    /// CoreBluetooth Central Manager Options
    public var options: Options
    
    public var peripherals: Set<Peripheral> {
        return Set(cache.peripherals.keys)
    }
    
    public var stateChanged: ((State) -> ())?
    
    /// The current state of the manager.
    public var state: State {
        return unsafeBitCast(internalManager.state, to: State.self)
    }
    
    public var isScanning: Bool {
         
        if #available(macOS 10.13, iOS 9.0, *) {
            return internalManager.isScanning
        } else {
            return queue.sync { [unowned self] in self.delegate.scan != nil }
        }
    }
    
    public var scanningChanged: ((Bool) -> ())?
    
    public var didDisconnect: ((Peripheral) -> ())?
    
    private lazy var internalManager = CBCentralManager(
        delegate: self.delegate,
        queue: self.queue,
        options: self.options.optionsDictionary
    )
    
    private lazy var queue = DispatchQueue(label: "\(type(of: self)) Queue")
        
    private lazy var delegate = Delegate(self)

    private var cache = Cache()
    
    // MARK: - Initialization
    
    /// Initialize with the specified options.
    ///
    /// - Parameter options: An optional dictionary containing initialization options for a central manager.
    /// For available options, see [Central Manager Initialization Options](apple-reference-documentation://ts1667590).
    public init(options: Options = Options()) {
        self.options = options
        _ = self.internalManager // initialize
    }
    
    // MARK: - Methods
    
    /// Scans for peripherals that are advertising services.
    public func scan(filterDuplicates: Bool = true,
                     _ foundDevice: @escaping (Result<ScanData<Peripheral, DarwinAdvertisementData>, Error>) -> ()) {
        
        return self.scan(filterDuplicates: filterDuplicates, with: [], foundDevice)
    }
    
    /// Scans for peripherals that are advertising services.
    public func scan(filterDuplicates: Bool = true,
                     with services: Set<BluetoothUUID>,
                     _ foundDevice: @escaping (Result<ScanData<Peripheral, DarwinAdvertisementData>, Error>) -> ()) {
                        
        let serviceUUIDs: [CBUUID]? = services.isEmpty ? nil : services.map { CBUUID($0) }
        
        let options: [String: Any] = [
            CBCentralManagerScanOptionAllowDuplicatesKey: NSNumber(value: filterDuplicates == false)
        ]
        
        assert(isScanning == false)
        
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                self.cache.peripherals.removeAll(keepingCapacity: true)
                guard self.state == .poweredOn
                    else { throw DarwinCentralError.invalidState(self.state) }
                self.log?("Scanning...")
                self.delegate.scan = foundDevice
                self.internalManager.scanForPeripherals(withServices: serviceUUIDs, options: options)
                assert(self.isScanning)
            } catch {
                self.delegate.scan = nil
                foundDevice(.failure(error))
            }
        }
    }
    
    /// Stops scanning for peripherals.
    public func stopScan() {
        queue.async {
            assert(self.isScanning)
            self.internalManager.stopScan()
            self.delegate.scan = nil
            assert(self.isScanning == false)
            self.log?("Discovered \(self.cache.peripherals.count) peripherals")
        }
    }
    
    /// Connect to the specifed peripheral.
    /// - Parameter peripheral: The peripheral to which the central is attempting to connect.
    public func connect(to peripheral: Peripheral,
                        timeout: TimeInterval = .gattDefaultTimeout,
                        completion: @escaping (Result<Void, Error>) -> ()) {
        
        connect(to: peripheral, timeout: timeout, options: [:], completion: completion)
    }
    
    /// Connect to the specifed peripheral.
    /// - Parameter peripheral: The peripheral to which the central is attempting to connect.
    /// - Parameter options: A dictionary to customize the behavior of the connection.
    /// For available options, see [Peripheral Connection Options](apple-reference-documentation://ts1667676).
    public func connect(to peripheral: Peripheral,
                        timeout: TimeInterval = .gattDefaultTimeout,
                        options: [String: Any],
                        completion: @escaping (Result<Void, Error>) -> ()) {
        
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                guard self.state == .poweredOn
                    else { throw DarwinCentralError.invalidState(self.state) }
                let corePeripheral = try self.peripheral(for: peripheral)
                self.delegate.connect[peripheral] = Completion(timeout: timeout, queue: self.queue, completion)
                assert(corePeripheral.state != .connected)
                // attempt to connect (does not timeout)
                self.internalManager.connect(corePeripheral, options: options)
            }
            catch {
                self.delegate.connect[peripheral] = nil
                completion(.failure(error))
            }
        }
    }
    
    /// Cancels an active or pending local connection to a peripheral.
    ///
    /// - Parameter The peripheral to which the central manager is either trying to connect or has already connected.
    internal func cancelConnection(for peripheral: Peripheral) {
        queue.async {
            self.cache.peripherals[peripheral].flatMap {
                self.internalManager.cancelPeripheralConnection($0)
            }
        }
    }
    
    /// Disconnect from the speciffied peripheral.
    public func disconnect(_ peripheral: Peripheral) {
        cancelConnection(for: peripheral)
    }
    
    /// Disconnect from all connected peripherals.
    public func disconnectAll() {
        queue.async { [unowned self] in
            self.cache.peripherals
                .values
                .forEach { self.internalManager.cancelPeripheralConnection($0) }
        }
    }
    
    /// Discover the specified services.
    public func discoverServices(_ services: [BluetoothUUID] = [],
                                 for peripheral: Peripheral,
                                 timeout: TimeInterval = .gattDefaultTimeout,
                                 completion: @escaping (Result<[Service<Peripheral, AttributeID>], Error>) -> ()) {
        
        let coreServices = services.isEmpty ? nil : services.map { CBUUID($0) }
        
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                guard self.state == .poweredOn
                    else { throw DarwinCentralError.invalidState(self.state) }
                let corePeripheral = try self.peripheral(for: peripheral)
                guard corePeripheral.state == .connected
                    else { throw CentralError.disconnected }
                // store completion block
                self.delegate.discoverServices[peripheral] = Completion(timeout: timeout, queue: self.queue, completion)
                // discover services
                corePeripheral.discoverServices(coreServices)
            }
            catch {
                self.delegate.discoverServices[peripheral] = nil
                completion(.failure(error))
            }
        }
    }
    
    /// Discover characteristics for the specified service.
    public func discoverCharacteristics(_ characteristics: [BluetoothUUID] = [],
                                        for service: Service<Peripheral, ObjectIdentifier>,
                                        timeout: TimeInterval = .gattDefaultTimeout,
                                        completion: @escaping (Result<[Characteristic<Peripheral, AttributeID>], Error>) -> ()) {
        
        let coreCharacteristics = characteristics.isEmpty ? nil : characteristics.map { CBUUID($0) }
        
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                guard self.state == .poweredOn
                    else { throw DarwinCentralError.invalidState(self.state) }
                let corePeripheral = try self.peripheral(for: service.peripheral)
                guard corePeripheral.state == .connected
                    else { throw CentralError.disconnected }
                let coreService = try self.service(for: service)
                self.delegate.discoverCharacteristics[service.peripheral] = Completion(timeout: timeout, queue: self.queue, completion)
                // discover characteristics
                corePeripheral.discoverCharacteristics(coreCharacteristics, for: coreService)
            }
            catch {
                self.delegate.discoverCharacteristics[service.peripheral] = nil
                completion(.failure(error))
            }
        }
    }
    
    /// Read characteristic value.
    public func readValue(for characteristic: Characteristic<Peripheral, ObjectIdentifier>,
                          timeout: TimeInterval = .gattDefaultTimeout,
                          completion: @escaping (Result<Data, Error>) -> ()) {
                
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                guard self.state == .poweredOn
                    else { throw DarwinCentralError.invalidState(self.state) }
                let corePeripheral = try self.peripheral(for: characteristic.peripheral)
                guard corePeripheral.state == .connected
                    else { throw CentralError.disconnected }
                let coreCharacteristic = try self.characteristic(for: characteristic)
                self.delegate.readCharacteristicValue[characteristic.peripheral] = Completion(timeout: timeout, queue: self.queue, completion)
                // read value
                corePeripheral.readValue(for: coreCharacteristic)
            }
            catch {
                self.delegate.readCharacteristicValue[characteristic.peripheral] = nil
                completion(.failure(error))
            }
        }
    }
    
    /// Write characteristic value.
    public func writeValue(_ data: Data,
                           for characteristic: Characteristic<Peripheral, ObjectIdentifier>,
                           withResponse: Bool = true,
                           timeout: TimeInterval = .gattDefaultTimeout,
                           completion: @escaping (Result<Void, Error>) -> ()) {
        
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                guard self.state == .poweredOn
                    else { throw DarwinCentralError.invalidState(self.state) }
                let corePeripheral = try self.peripheral(for: characteristic.peripheral)
                guard corePeripheral.state == .connected
                    else { throw CentralError.disconnected }
                let coreCharacteristic = try self.characteristic(for: characteristic)
                
                // write value with response
                if withResponse {
                    
                    // calls `peripheral:didWriteValueForCharacteristic:error:` only
                    // if you specified the write type as `.withResponse`.
                    self.delegate.writeCharacteristicValue[characteristic.peripheral] = Completion(timeout: timeout, queue: self.queue, completion)
                    
                    // write request (will call delegate method)
                    corePeripheral.writeValue(data, for: coreCharacteristic, type: .withResponse)
                } else {
                    
                    // flush write messages if supported
                    if #available(macOS 13, iOS 11, tvOS 11, watchOS 4, *),
                        corePeripheral.canSendWriteWithoutResponse == false {
                        // wait until write queue is flushed
                        self.delegate.flushWriteWithoutResponse[characteristic.peripheral] = Completion(timeout: timeout, queue: self.queue) { _ in
                            // write command (if not blob)
                            corePeripheral.writeValue(data, for: coreCharacteristic, type: .withoutResponse)
                            completion(.success(()))
                        }
                    } else {
                        // have no idea if write will be queued or executed immediately
                        // try after a small delay
                        self.queue.asyncAfter(deadline: .now() + 1.5) {
                            // write command (if not blob)
                            corePeripheral.writeValue(data, for: coreCharacteristic, type: .withoutResponse)
                            completion(.success(()))
                        }
                    }
                }
            }
            catch {
                self.delegate.writeCharacteristicValue[characteristic.peripheral] = nil
                completion(.failure(error))
            }
        }
    }
    
    /// Subscribe to notifications for the specified characteristic.
    public func notify(_ notification: ((Data) -> ())?,
                       for characteristic: Characteristic<Peripheral, ObjectIdentifier>,
                       timeout: TimeInterval = .gattDefaultTimeout,
                       completion: @escaping (Result<Void, Error>) -> ()) {
        
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                guard self.state == .poweredOn
                    else { throw DarwinCentralError.invalidState(self.state) }
                let corePeripheral = try self.peripheral(for: characteristic.peripheral)
                guard corePeripheral.state == .connected
                    else { throw CentralError.disconnected }
                let coreCharacteristic = try self.characteristic(for: characteristic)
                self.delegate.setNotification[characteristic.peripheral] = Completion(timeout: timeout, queue: self.queue, completion)
                // read value
                corePeripheral.setNotifyValue(notification != nil, for: coreCharacteristic)
            }
            catch {
                self.delegate.readCharacteristicValue[characteristic.peripheral] = nil
                completion(.failure(error))
            }
        }
    }
    
    /// Get the maximum transmission unit for the specified peripheral.
    public func maximumTransmissionUnit(for peripheral: Peripheral, completion: @escaping (Result<ATTMaximumTransmissionUnit, Error>) -> ()) {
        
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                guard self.state == .poweredOn
                    else { throw DarwinCentralError.invalidState(self.state) }
                let corePeripheral = try self.peripheral(for: peripheral)
                guard corePeripheral.state == .connected
                    else { throw CentralError.disconnected }
                // get MTU
                let mtu: ATTMaximumTransmissionUnit
                if #available(macOS 10.12, iOS 9.0, tvOS 9.0, watchOS 4.0, *) {
                    let rawValue = corePeripheral.maximumWriteValueLength(for: .withoutResponse) + 3
                    assert((corePeripheral.value(forKey: "mtuLength") as! NSNumber).intValue == rawValue)
                    mtu = ATTMaximumTransmissionUnit(rawValue: UInt16(rawValue)) ?? .default
                } else {
                    mtu = .default
                }
                completion(.success(mtu))
            }
            catch {
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Private Methods
    
    internal func peripheral(for peripheral: Peripheral) throws -> CBPeripheral {
        guard let corePeripheral = self.cache.peripherals[peripheral]
            else { throw CentralError.unknownPeripheral }
        return corePeripheral
    }
    
    internal func service(for service: Service<Peripheral, AttributeID>) throws -> CBService {
        let corePeripheral = try peripheral(for: service.peripheral)
        guard let coreServices = corePeripheral.services,
            let coreService = coreServices.first(where: { ObjectIdentifier($0) == service.id })
            else { throw CentralError.invalidAttribute(service.uuid) }
        return coreService
    }
    
    internal func characteristic(for characteristic: Characteristic<Peripheral, AttributeID>) throws -> CBCharacteristic {
        let corePeripheral = try peripheral(for: characteristic.peripheral)
        let coreCharacteristics = (corePeripheral.services ?? []).reduce([], { $0 + ($1.characteristics ?? []) })
        guard let coreCharacteristic = coreCharacteristics.first(where: { ObjectIdentifier($0) == characteristic.id })
            else { throw CentralError.invalidAttribute(characteristic.uuid) }
        return coreCharacteristic
    }
}

// MARK: - Supporting Types

public extension DarwinCentral {
    
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
                options[CBPeripheralManagerOptionShowPowerAlertKey] = showPowerAlert as NSNumber
            }
            options[CBPeripheralManagerOptionRestoreIdentifierKey] = restoreIdentifier
            return options
        }
    }
}

internal extension DarwinCentral {
    
    @objc(GATTCentralManagerDelegate)
    final class Delegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
        
        private(set) weak var central: DarwinCentral!
        
        var log: ((String) -> ())? {
            return central?.log
        }
        
        var scan: ((Result<ScanData<Peripheral, Advertisement>, Error>) -> ())?
        var connect = [Peripheral: Completion<Void>]()
        var discoverServices = [Peripheral: Completion<[Service<Peripheral, AttributeID>]>]()
        var discoverCharacteristics = [Peripheral: Completion<[Characteristic<Peripheral, AttributeID>]>]()
        var readCharacteristicValue = [Peripheral: Completion<Data>]()
        var writeCharacteristicValue = [Peripheral: Completion<Void>]()
        var flushWriteWithoutResponse = [Peripheral: Completion<Void>]()
        var setNotification = [Peripheral: Completion<Void>]()
        var notifications = [Peripheral: (Data) -> ()]()
        
        fileprivate init(_ central: DarwinCentral) {
            super.init()
            self.central = central
        }
        
        // MARK: - CBCentralManagerDelegate
        
        func centralManagerDidUpdateState(_ centralManager: CBCentralManager) {
            assert(self.central != nil)
            assert(self.central?.internalManager === centralManager)
            let state = unsafeBitCast(centralManager.state, to: DarwinBluetoothState.self)
            log?("Did update state \(state)")
            self.central?.stateChanged?(state)
            assert(self.central.state == state)
        }
        
        func centralManager(_ centralManager: CBCentralManager, willRestoreState state: [String : Any]) {
            assert(self.central != nil)
            assert(self.central?.internalManager === centralManager)
            // An array of peripherals for use when restoring the state of a central manager.
            if #available(macOS 10.13, *) {
                if let peripherals = state[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
                    peripherals.forEach {
                        let peripheral = Peripheral($0)
                        self.central.cache.peripherals[peripheral] = $0
                    }
                }
            }
        }
        
        func centralManager(_ centralManager: CBCentralManager,
                            didDiscover peripheral: CBPeripheral,
                            advertisementData: [String : Any],
                            rssi: NSNumber) {
            
            assert(self.central != nil)
            assert(self.central?.internalManager === centralManager)
            
            let identifier = Peripheral(peripheral)
            let advertisement = Advertisement(advertisementData)
            let scanResult = ScanData(peripheral: identifier,
                                      date: Date(),
                                      rssi: rssi.doubleValue,
                                      advertisementData: advertisement,
                                      isConnectable: advertisement.isConnectable ?? false)
            
            self.central.cache.peripherals[identifier] = peripheral
            guard let scan = self.scan
                else { assertionFailure(); return }
            scan(.success(scanResult))
        }
        
        func centralManager(_ centralManager: CBCentralManager, didConnect corePeripheral: CBPeripheral) {
            
            log?("Did connect to peripheral \(corePeripheral.gattIdentifier.uuidString)")
            
            assert(corePeripheral.state != .disconnected, "Should be connected")
            assert(self.central != nil)
            assert(self.central?.internalManager === centralManager)
            
            let peripheral = Peripheral(corePeripheral)
            guard let callback = self.connect[peripheral]
                else { assertionFailure("Missing subject"); return }
            callback.didComplete(.success(()))
            self.connect[peripheral] = nil
        }
        
        func centralManager(_ centralManager: CBCentralManager, didFailToConnect corePeripheral: CBPeripheral, error: Swift.Error?) {
            
            log?("Did fail to connect to peripheral \(corePeripheral.gattIdentifier.uuidString) (\(error!))")
            
            assert(corePeripheral.state != .disconnected, "Should be connected")
            assert(self.central != nil)
            assert(self.central?.internalManager === centralManager)
            assert(error != nil)
            
            let peripheral = Peripheral(corePeripheral)
            guard let callback = self.connect[peripheral]
                else { assertionFailure("Missing callback"); return }
            callback.didComplete(.failure(error!))
            self.connect[peripheral] = nil
        }
        
        func centralManager(_ central: CBCentralManager, didDisconnectPeripheral corePeripheral: CBPeripheral, error: Swift.Error?) {
                        
            if let error = error {
                log?("Did disconnect peripheral \(corePeripheral.gattIdentifier.uuidString) due to error \(error.localizedDescription)")
            } else {
                log?("Did disconnect peripheral \(corePeripheral.gattIdentifier.uuidString)")
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
            
            log?("Peripheral \(corePeripheral.gattIdentifier.uuidString) is ready to send write without response")
            
            let peripheral = Peripheral(corePeripheral)
            self.flushWriteWithoutResponse[peripheral]?.didComplete(.success(()))
            self.flushWriteWithoutResponse[peripheral] = nil
        }
    }
}

internal extension DarwinCentral {
    
    struct Cache {
        var peripherals = [Peripheral: CBPeripheral]()
    }
    
    final class Completion <Output> {
                
        let timeout: TimeInterval
                
        private let block: (Result<Output, Error>) -> ()
        
        private(set) var didComplete: Bool = false
        
        fileprivate init(timeout: TimeInterval,
                         queue: DispatchQueue = .global(),
                         _ block: @escaping (Result<Output, Error>) -> ()) {
            self.timeout = timeout
            self.block = block
            // call timeout after interval
            queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.didTimeout()
            }
        }
        
        func didComplete(_ result: Result<Output, Error>) {
            precondition(didComplete == false)
            didComplete = true
            block(result)
        }
        
        private func didTimeout() {
            guard didComplete == false
                else { return }
            didComplete(.failure(CentralError.timeout))
        }
    }
}

#endif
