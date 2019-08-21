//
//  DarwinCentral.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/3/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import Foundation
import Bluetooth
import GATT

#if canImport(CoreBluetooth)
    
import CoreBluetooth

/// The platform specific peripheral.

@objc
public final class DarwinCentral: NSObject, CentralProtocol, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    public typealias Advertisement = DarwinAdvertisementData
    
    // MARK: - Properties
    
    public var log: ((String) -> ())?
    
    public var options: Options
    
    public var stateChanged: (DarwinBluetoothState) -> () = { _ in }
    
    public var state: DarwinBluetoothState {
        return unsafeBitCast(internalManager.state, to: DarwinBluetoothState.self)
    }
    
    public var isScanning: Bool {
        
        if #available(macOS 10.13, iOS 9.0, *) {
            return internalManager.isScanning
        } else {
            return accessQueue.sync { [unowned self] in self.internalState.scan.foundDevice != nil }
        }
    }
    
    public var didDisconnect: ((Peripheral) -> ())?
    
    // MARK: - Private Properties
    
    private lazy var internalManager: CBCentralManager = CBCentralManager(delegate: self, queue: self.managerQueue, options: self.options.optionsDictionary)
    
    internal lazy var managerQueue: DispatchQueue = DispatchQueue(label: "\(type(of: self)) Manager Queue")
    
    internal lazy var accessQueue: DispatchQueue = DispatchQueue(label: "\(type(of: self)) Access Queue")
    
    internal private(set) var internalState = InternalState()
    
    // MARK: - Initialization
    
    /// Initialize with the specified options.
    ///
    /// - Parameter options: An optional dictionary containing initialization options for a central manager.
    /// For available options, see [Central Manager Initialization Options](apple-reference-documentation://ts1667590).
    public init(options: Options) {
        
        self.options = options
        
        super.init()
        
        let _ = self.internalManager // initialize manager
    }
    
    public override convenience init() {
        
        self.init(options: Options())
    }
    
    // MARK: - Methods
    
    public func scan(filterDuplicates: Bool = true,
                     foundDevice: @escaping (ScanData<Peripheral, Advertisement>) -> ()) throws {
        
        try scan(filterDuplicates: filterDuplicates, with: [], foundDevice: foundDevice)
    }
    
    public func scan(filterDuplicates: Bool = true,
                     with services: Set<BluetoothUUID>,
                     foundDevice: @escaping (ScanData<Peripheral, Advertisement>) -> ()) throws {
        
        guard state == .poweredOn
            else { throw DarwinCentralError.invalidState(state) }
        
        let serviceUUIDs: [CBUUID]? = services.isEmpty ? nil : services.map { CBUUID($0) }
        
        let options: [String: Any] = [
            CBCentralManagerScanOptionAllowDuplicatesKey: NSNumber(value: filterDuplicates == false)
        ]
        
        accessQueue.sync { [unowned self] in
            self.internalState.scan.peripherals = [:]
            self.internalState.scan.foundDevice = foundDevice
        }
        
        // store semaphore
        let semaphore = Semaphore(timeout: 60 * 10, operation: .scan)
        accessQueue.sync { [unowned self] in self.internalState.scan.semaphore = semaphore }
        defer { accessQueue.sync { [unowned self] in self.internalState.scan.semaphore = nil } }
        
        self.log?("Scanning...")
        
        self.internalManager.scanForPeripherals(withServices: serviceUUIDs, options: options)
        
        assert(self.isScanning, "Should be in scanning state")
        
        // wait
        try semaphore.wait()
        
        accessQueue.sync { [unowned self] in
            self.internalState.scan.foundDevice = nil
        }
        
        self.log?("Did discover \(self.internalState.scan.peripherals.count) peripherals")
    }
    
    public func stopScan() {
        
        self.log?("Stop scanning")
        
        accessQueue.async { [unowned self] in
            self.internalState.scan.semaphore?.stopWaiting()
            self.internalState.scan.semaphore = nil
        }
        
        self.internalManager.stopScan()
    }
    
    public func connect(to peripheral: Peripheral, timeout: TimeInterval = .gattDefaultTimeout) throws {
        
        try connect(to: peripheral, timeout: timeout, options: [:])
    }
    
    /// A dictionary to customize the behavior of the connection.
    ///
    /// For available options, see [Peripheral Connection Options](apple-reference-documentation://ts1667676).
    public func connect(to peripheral: Peripheral,
                        timeout: TimeInterval = .gattDefaultTimeout,
                        options: [String: Any]) throws {
        
        guard state == .poweredOn
            else { throw DarwinCentralError.invalidState(state) }
        
        guard let corePeripheral = accessQueue.sync(execute: { [unowned self] in self.peripheral(peripheral) })
            else { throw CentralError.unknownPeripheral }
        
        guard corePeripheral.state != .connected
            else { return } // already connected
        
        // store semaphore
        let semaphore = Semaphore(timeout: timeout, operation: .connect(peripheral))
        accessQueue.sync { [unowned self] in self.internalState.connect.semaphore = semaphore }
        defer { accessQueue.sync { [unowned self] in self.internalState.connect.semaphore = nil } }
        
        // attempt to connect (does not timeout)
        self.internalManager.connect(corePeripheral, options: options)
        
        // throw async error
        do { try semaphore.wait() }
            
        catch CentralError.timeout {
            
            // cancel connection if we timeout
            self.internalManager.cancelPeripheralConnection(corePeripheral)
            throw CentralError.timeout
        }
        
        assert(corePeripheral.state == .connected, "Peripheral should be connected")
    }
    
    public func disconnect(peripheral: Peripheral) {
        
        guard let corePeripheral = accessQueue.sync(execute: { [unowned self] in self.peripheral(peripheral) })
            else { assertionFailure("Unknown peripheral \(peripheral)"); return }
        
        internalManager.cancelPeripheralConnection(corePeripheral)
    }
    
    public func disconnectAll() {
        
        accessQueue.sync { [unowned self] in
            
            self.internalState.scan.peripherals.values.forEach { [unowned self] in
                self.internalManager.cancelPeripheralConnection($0.peripheral)
            }
        }
    }
    
    public func discoverServices(_ services: [BluetoothUUID] = [],
                                 for peripheral: Peripheral,
                                 timeout: TimeInterval = .gattDefaultTimeout) throws -> [Service<Peripheral>] {
        
        guard state == .poweredOn
            else { throw DarwinCentralError.invalidState(state) }
        
        let corePeripheral = try accessQueue.sync { [unowned self] in
            try self.connectedPeripheral(peripheral)
        }
        
        guard corePeripheral.state == .connected
            else { throw CentralError.disconnected }
        
        // store semaphore
        let semaphore = Semaphore(timeout: timeout, operation: .discoverServices(peripheral))
        accessQueue.sync { [unowned self] in self.internalState.discoverServices.semaphore = semaphore }
        defer { accessQueue.sync { [unowned self] in self.internalState.discoverServices.semaphore = nil } }
        
        let coreServices = services.isEmpty ? nil : services.map { CBUUID($0) }
        
        // start discovery
        corePeripheral.discoverServices(coreServices)
        
        // wait
        try semaphore.wait()
        
        return accessQueue.sync { [unowned self] in
            self.internalState.cache[peripheral]?.services.values.map {
                Service(identifier: $0.key,
                        uuid: BluetoothUUID($0.value.uuid),
                        peripheral: peripheral,
                        isPrimary: $0.value.isPrimary)
            } ?? []
        }
    }
    
    public func discoverCharacteristics(_ characteristics: [BluetoothUUID] = [],
                                        for service: Service<Peripheral>,
                                        timeout: TimeInterval = .gattDefaultTimeout) throws -> [Characteristic<Peripheral>] {
        
        guard state == .poweredOn
            else { throw DarwinCentralError.invalidState(state) }
        
        let corePeripheral = try accessQueue.sync { [unowned self] in
            try self.connectedPeripheral(service.peripheral)
        }
        
        guard corePeripheral.state == .connected
            else { throw CentralError.disconnected }
        
        let coreService: CBService = try self.accessQueue.sync { [unowned self] in
            
            guard let coreService = self.internalState.cache[service.peripheral]?.services.values[service.identifier]
                else { throw CentralError.invalidAttribute(service.uuid) }
            
            return coreService
        }
        
        // store semaphore
        let semaphore = Semaphore(timeout: timeout, operation: .discoverCharacteristics(service))
        accessQueue.sync { [unowned self] in self.internalState.discoverCharacteristics.semaphore = semaphore }
        defer { accessQueue.sync { [unowned self] in self.internalState.discoverCharacteristics.semaphore = nil } }
        
        let coreCharacteristics = characteristics.isEmpty ? nil : characteristics.map { CBUUID($0) }
        
        corePeripheral.discoverCharacteristics(coreCharacteristics, for: coreService)
        
        // wait
        try semaphore.wait()
        
        // get cached characteristics
        let charachertisticCache = accessQueue.sync { [unowned self] in
            self.internalState.cache[service.peripheral]?.characteristics.values ?? [:]
        }
        
        return charachertisticCache.map {
            Characteristic(identifier: $0.key,
                           uuid: BluetoothUUID($0.value.attribute.uuid),
                           peripheral: service.peripheral,
                           properties: Characteristic<Peripheral>.Property.from(coreBluetooth: $0.value.attribute.properties))
        }
    }
    
    public func readValue(for characteristic: Characteristic<Peripheral>,
                          timeout: TimeInterval = .gattDefaultTimeout) throws -> Data {
        
        guard state == .poweredOn
            else { throw DarwinCentralError.invalidState(state) }
        
        let corePeripheral = try accessQueue.sync { [unowned self] in
            try self.connectedPeripheral(characteristic.peripheral)
        }
        
        guard corePeripheral.state == .connected
            else { throw CentralError.disconnected }
        
        let coreCharacteristic: CBCharacteristic = try self.accessQueue.sync { [unowned self] in
            
            guard let coreCharacteristic = self.internalState.cache[characteristic.peripheral]?.characteristics.values[characteristic.identifier]?.attribute
                else { throw CentralError.invalidAttribute(characteristic.uuid) }
            
            return coreCharacteristic
        }
        
        // store semaphore
        let semaphore = Semaphore(timeout: timeout, operation: .readCharacteristic(characteristic))
        accessQueue.sync { [unowned self] in self.internalState.readCharacteristic.semaphore = semaphore }
        defer { accessQueue.sync { [unowned self] in self.internalState.readCharacteristic.semaphore = nil } }
        
        corePeripheral.readValue(for: coreCharacteristic)
        
        // wait
        try semaphore.wait()
        
        return coreCharacteristic.value ?? Data()
    }
    
    public func writeValue(_ data: Data,
                           for characteristic: Characteristic<Peripheral>,
                           withResponse: Bool = true,
                           timeout: TimeInterval = .gattDefaultTimeout) throws {
        
        guard state == .poweredOn
            else { throw DarwinCentralError.invalidState(state) }
        
        let corePeripheral = try accessQueue.sync { [unowned self] in
            try self.connectedPeripheral(characteristic.peripheral)
        }
        
        guard corePeripheral.state == .connected
            else { throw CentralError.disconnected }
        
        let coreCharacteristic: CBCharacteristic = try self.accessQueue.sync { [unowned self] in
            
            guard let coreCharacteristic = self.internalState.cache[characteristic.peripheral]?.characteristics.values[characteristic.identifier]?.attribute
                else { throw CentralError.invalidAttribute(characteristic.uuid) }
            
            return coreCharacteristic
        }
        
        if withResponse {
            
            // write request
            corePeripheral.writeValue(data, for: coreCharacteristic, type: .withResponse)
            
            // calls `peripheral:didWriteValueForCharacteristic:error:` only
            // if you specified the write type as `.withResponse`.
            let semaphore = Semaphore(timeout: timeout, operation: .writeCharacteristic(characteristic))
            accessQueue.sync { [unowned self] in self.internalState.writeCharacteristic.semaphore = semaphore }
            defer { accessQueue.sync { [unowned self] in self.internalState.writeCharacteristic.semaphore = nil } }
            try semaphore.wait()
            
        } else {
            
            // flush write messages
            if #available(macOS 13, iOS 11, tvOS 11, watchOS 4, *) {
                if corePeripheral.canSendWriteWithoutResponse == false {
                    let semaphore = Semaphore(
                        timeout: options.writeWithoutResponseTimeout,
                        operation: .flushWriteWithoutResponse(characteristic.peripheral)
                    )
                    accessQueue.sync { [unowned self] in
                        self.internalState.flushWriteWithoutResponse.semaphore = semaphore
                    }
                    defer {
                        accessQueue.sync { [unowned self] in self.internalState.flushWriteWithoutResponse.semaphore = nil
                        }
                    }
                    do { try semaphore.wait() }
                    catch { log?("Timeout waiting for write without response availability") }
                }
            } else {
                sleep(1)
            }
            
            // write command (if not blob)
            corePeripheral.writeValue(data, for: coreCharacteristic, type: .withoutResponse)
        }
    }
    
    public func notify(_ notification: ((Data) -> ())?,
                       for characteristic: Characteristic<Peripheral>,
                       timeout: TimeInterval = .gattDefaultTimeout) throws {
        
        guard state == .poweredOn
            else { throw DarwinCentralError.invalidState(state) }
        
        let corePeripheral = try accessQueue.sync { [unowned self] in
            try self.connectedPeripheral(characteristic.peripheral)
        }
        
        let coreCharacteristic: CBCharacteristic = try self.accessQueue.sync { [unowned self] in
            
            guard let coreCharacteristic = self.internalState.cache[characteristic.peripheral]?.characteristics.values[characteristic.identifier]?.attribute
                else { throw CentralError.invalidAttribute(characteristic.uuid) }
            
            return coreCharacteristic
        }
        
        // store semaphore
        let semaphore = Semaphore(timeout: timeout, operation: .updateCharacteristicNotificationState(characteristic))
        accessQueue.sync { [unowned self] in self.internalState.notify.semaphore = semaphore }
        defer { accessQueue.sync { [unowned self] in self.internalState.notify.semaphore = nil } }
        
        let isEnabled = notification != nil
        
        corePeripheral.setNotifyValue(isEnabled, for: coreCharacteristic)
        
        // server need to confirm descriptor write
        try semaphore.wait()
        
        accessQueue.sync { [unowned self] in
            
            var cache = self.internalState.cache[characteristic.peripheral] ?? Cache()
            cache.characteristics.values[characteristic.identifier] = (coreCharacteristic, notification)
            self.internalState.cache[characteristic.peripheral] = cache
        }
    }
    
    public func maximumTransmissionUnit(for peripheral: Peripheral) throws -> ATTMaximumTransmissionUnit {
        
        guard state == .poweredOn
            else { throw DarwinCentralError.invalidState(state) }
        
        let corePeripheral = try accessQueue.sync { [unowned self] in
            try self.connectedPeripheral(peripheral)
        }
        
        if #available(iOS 9.0, macOS 10.12, *) {
            
            let mtu = corePeripheral.maximumWriteValueLength(for: .withoutResponse) + 3
            
            assert((corePeripheral.value(forKey: "mtuLength") as! NSNumber).intValue == mtu)
            
            return ATTMaximumTransmissionUnit(rawValue: UInt16(mtu)) ?? .default
            
        } else {
            
            return .default
        }
    }
    
    // MARK: - Private Methods
    
    private func peripheral(_ peripheral: Peripheral) -> CBPeripheral? {
        
        return self.internalState.scan.peripherals[peripheral]?.peripheral
    }
    
    private func connectedPeripheral(_ peripheral: Peripheral) throws -> CBPeripheral {
        
        guard let corePeripheral = self.peripheral(peripheral)
            else { throw CentralError.unknownPeripheral }
        
        guard corePeripheral.state == .connected
            else { throw CentralError.disconnected }
        
        return corePeripheral
    }
    
    // MARK: - CBCentralManagerDelegate
    
    @objc(centralManagerDidUpdateState:)
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        
        let state = unsafeBitCast(central.state, to: DarwinBluetoothState.self)
        
        log?("Did update state \(state)")
        
        stateChanged(state)
    }
    
    @objc(centralManager:didDiscoverPeripheral:advertisementData:RSSI:)
    public func centralManager(_ central: CBCentralManager,
                               didDiscover peripheral: CBPeripheral,
                               advertisementData: [String : Any],
                               rssi: NSNumber) {
        
        if peripheral.delegate == nil {
            
            peripheral.delegate = self
        }
        
        let identifier = Peripheral(peripheral)
        
        let advertisement = Advertisement(advertisementData)
        
        let scanResult = ScanData(peripheral: identifier,
                                  date: Date(),
                                  rssi: rssi.doubleValue,
                                  advertisementData: Advertisement(advertisementData),
                                  isConnectable: advertisement.isConnectable ?? false)
        
        accessQueue.sync { [unowned self] in
            
            self.internalState.scan.peripherals[identifier] = (peripheral, scanResult)
            self.internalState.scan.foundDevice?(scanResult)
        }
    }
    
    @objc(centralManager:didConnectPeripheral:)
    public func centralManager(_ central: CBCentralManager, didConnect corePeripheral: CBPeripheral) {
        
        log?("Did connect to peripheral \(corePeripheral.gattIdentifier.uuidString)")
        
        assert(corePeripheral.state != .disconnected, "Should be connected")
        
        accessQueue.sync { [unowned self] in
            self.internalState.connect.semaphore?.stopWaiting()
            self.internalState.connect.semaphore = nil
            self.internalState.cache[Peripheral(corePeripheral)] = Cache() // initialize cache
        }
    }
    
    @objc(centralManager:didFailToConnectPeripheral:error:)
    public func centralManager(_ central: CBCentralManager, didFailToConnect corePeripheral: CBPeripheral, error: Swift.Error?) {
        
        log?("Did fail to connect to peripheral \(corePeripheral.gattIdentifier.uuidString) (\(error!))")
        
        accessQueue.sync { [unowned self] in
            self.internalState.connect.semaphore?.stopWaiting(error)
            self.internalState.connect.semaphore = nil
        }
    }
    
    @objc(centralManager:didDisconnectPeripheral:error:)
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral corePeripheral: CBPeripheral, error: Swift.Error?) {
        
        let peripheral = Peripheral(corePeripheral)
        
        if let error = error {
            log?("Did disconnect peripheral \(corePeripheral.gattIdentifier.uuidString) due to error \(error.localizedDescription)")
        } else {
            log?("Did disconnect peripheral \(corePeripheral.gattIdentifier.uuidString)")
        }
        
        self.didDisconnect?(peripheral)
        
        // cancel all actions that require an active connection
        let semaphores = [
            internalState.discoverServices.semaphore,
            internalState.discoverCharacteristics.semaphore,
            internalState.writeCharacteristic.semaphore,
            internalState.flushWriteWithoutResponse.semaphore,
            internalState.readCharacteristic.semaphore,
            internalState.notify.semaphore
        ]
        
        semaphores
            .filter { $0?.operation.peripheral == peripheral }
            .compactMap { $0 }
            .forEach { $0.stopWaiting(CentralError.disconnected) }
    }
    
    // MARK: - CBPeripheralDelegate
    
    @objc(peripheral:didDiscoverServices:)
    public func peripheral(_ corePeripheral: CBPeripheral, didDiscoverServices error: Swift.Error?) {
        
        if let error = error {
            
            log?("Error discovering services (\(error))")
            
        } else {
            
            log?("Peripheral \(corePeripheral.gattIdentifier.uuidString) did discover \(corePeripheral.services?.count ?? 0) services")
        }
        
        accessQueue.sync { [unowned self] in
            
            // cache
            let peripheral = Peripheral(corePeripheral)
            var cache = self.internalState.cache[peripheral] ?? Cache()
            cache.update(corePeripheral.services ?? [])
            self.internalState.cache[peripheral] = cache
            
            // semaphore
            self.internalState.discoverServices.semaphore?.stopWaiting(error)
            self.internalState.discoverServices.semaphore = nil
        }
    }
    
    @objc(peripheral:didDiscoverCharacteristicsForService:error:)
    public func peripheral(_ corePeripheral: CBPeripheral,
                           didDiscoverCharacteristicsFor coreService: CBService,
                           error: Swift.Error?) {
        
        if let error = error {
            
            log?("Error discovering characteristics (\(error))")
            
        } else {
            
            log?("Peripheral \(corePeripheral.gattIdentifier.uuidString) did discover \(coreService.characteristics?.count ?? 0) characteristics for service \(coreService.uuid.uuidString)")
        }
        
        accessQueue.sync { [unowned self] in
            
            // cache
            let peripheral = Peripheral(corePeripheral)
            var cache = self.internalState.cache[peripheral] ?? Cache()
            cache.insert(coreService.characteristics ?? [], for: coreService)
            self.internalState.cache[peripheral] = cache
            
            // semaphore
            self.internalState.discoverCharacteristics.semaphore?.stopWaiting(error)
            self.internalState.discoverCharacteristics.semaphore = nil
        }
    }
    
    @objc(peripheral:didUpdateValueForCharacteristic:error:)
    public func peripheral(_ corePeripheral: CBPeripheral, didUpdateValueFor coreCharacteristic: CBCharacteristic, error: Swift.Error?) {
        
        let data = coreCharacteristic.value ?? Data()
        
        if let error = error {
            
            log?("Error reading characteristic (\(error))")
            
        } else {
            
            log?("Peripheral \(corePeripheral.gattIdentifier.uuidString) did update value for characteristic \(coreCharacteristic.uuid.uuidString)")
        }
        
        // Invoked when you retrieve a specified characteristic’s value,
        // or when the peripheral device notifies your app that the characteristic’s value has changed.
        accessQueue.sync { [unowned self] in
            
            // read operation
            if let semaphore = self.internalState.readCharacteristic.semaphore {
                
                semaphore.stopWaiting(error)
                self.internalState.readCharacteristic.semaphore = nil
                
            } else {
                
                // notification
                assert(error == nil, "Notifications should never fail")
                
                guard let cache = self.internalState.cache[Peripheral(corePeripheral)],
                    let characteristicCache = cache.characteristics.values.first(where: { $0.value.attribute === coreCharacteristic })?.value
                    else { assertionFailure("Invalid characteristic \(coreCharacteristic.uuid)"); return }
                
                guard let notification = characteristicCache.notification
                    else { assertionFailure("Unexpected notification for \(coreCharacteristic.uuid)"); return }
                
                // notify
                notification(data)
            }
        }
    }
    
    @objc(peripheral:didWriteValueForCharacteristic:error:)
    public func peripheral(_ corePeripheral: CBPeripheral, didWriteValueFor coreCharacteristic: CBCharacteristic, error: Swift.Error?) {
        
        if let error = error {
            
            log?("Error writing characteristic (\(error))")
            
        } else {
            
            log?("Peripheral \(corePeripheral.gattIdentifier.uuidString) did write value for characteristic \(coreCharacteristic.uuid.uuidString)")
        }
        
        accessQueue.sync { [unowned self] in
            self.internalState.writeCharacteristic.semaphore?.stopWaiting(error)
            self.internalState.writeCharacteristic.semaphore = nil
        }
    }
    
    @objc
    public func peripheral(_ corePeripheral: CBPeripheral,
                           didUpdateNotificationStateFor coreCharacteristic: CBCharacteristic,
                           error: Swift.Error?) {
        
        if let error = error {
            
            log?("Error setting notifications for characteristic (\(error))")
            
        } else {
            
            log?("Peripheral \(corePeripheral.gattIdentifier.uuidString) did update notification state for characteristic \(coreCharacteristic.uuid.uuidString)")
        }
        
        accessQueue.sync { [unowned self] in
            self.internalState.notify.semaphore?.stopWaiting(error)
            self.internalState.notify.semaphore = nil
        }
    }
    
    @objc(peripheral:didUpdateValueForDescriptor:error:)
    public func peripheral(_ peripheral: CBPeripheral,
                           didUpdateValueFor descriptor: CBDescriptor,
                           error: Swift.Error?) {
        
        // TODO: Read Descriptor Value
    }
    
    @objc
    public func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        
        log?("Peripheral \(peripheral.gattIdentifier.uuidString) is ready to send write without response")
        
        accessQueue.sync { [unowned self] in
            self.internalState.flushWriteWithoutResponse.semaphore?.stopWaiting()
            self.internalState.flushWriteWithoutResponse.semaphore = nil
        }
    }
}

// MARK: - Supporting Types

public extension DarwinCentral {
    
    /// Central Peer
    ///
    /// Represents a remote central device that has connected to an app implementing the peripheral role on a local device.
    struct Peripheral: Peer {
        
        public let identifier: UUID
        
        init(_ peripheral: CBPeripheral) {
            
            self.identifier = peripheral.gattIdentifier
        }
    }
}

public extension DarwinCentral {
    
    typealias Error = DarwinCentralError
}

public extension DarwinCentral {
    
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
         How long to wait for write without response to be ready.
         */
        public var writeWithoutResponseTimeout: TimeInterval
        
        /**
         Initialize options.
         */
        public init(showPowerAlert: Bool = false,
                    restoreIdentifier: String? = nil,
                    writeWithoutResponseTimeout: TimeInterval = 3.0) {
            
            self.showPowerAlert = showPowerAlert
            self.restoreIdentifier = restoreIdentifier
            self.writeWithoutResponseTimeout = writeWithoutResponseTimeout
        }
        
        internal var optionsDictionary: [String: Any] {
            
            var options = [String: Any](minimumCapacity: 2)
            if showPowerAlert {
                options[CBPeripheralManagerOptionShowPowerAlertKey] = showPowerAlert as NSNumber
            }
            options[CBPeripheralManagerOptionRestoreIdentifierKey] = self.restoreIdentifier
            
            return options
        }
    }
}

internal extension DarwinCentral {
    
    struct InternalState {
        
        fileprivate init() { }
        
        var cache = [Peripheral: Cache]()
        
        var scan = Scan()
        
        struct Scan {
            
            var semaphore: Semaphore?
            
            var peripherals = [Peripheral: (peripheral: CBPeripheral, scanResult: ScanData<Peripheral, Advertisement>)]()
            
            var foundDevice: ((ScanData<Peripheral, Advertisement>) -> ())?
        }
        
        var connect = Connect()
        
        struct Connect {
            
            var semaphore: Semaphore?
        }
        
        var discoverServices = DiscoverServices()
        
        struct DiscoverServices {
            
            var semaphore: Semaphore?
        }
        
        var discoverCharacteristics = DiscoverCharacteristics()
        
        struct DiscoverCharacteristics {
            
            var semaphore: Semaphore?
        }
        
        var readCharacteristic = ReadCharacteristic()
        
        struct ReadCharacteristic {
            
            var semaphore: Semaphore?
        }
        
        var writeCharacteristic = WriteCharacteristic()
        
        struct WriteCharacteristic {
            
            var semaphore: Semaphore?
        }
        
        var flushWriteWithoutResponse = FlushWriteWithoutResponse()
        
        struct FlushWriteWithoutResponse {
            
            var semaphore: Semaphore?
        }
        
        var notify = Notify()
        
        struct Notify {
            
            var semaphore: Semaphore?
        }
    }
    
    enum Operation {
        
        case scan
        case connect(Peripheral)
        case discoverServices(Peripheral)
        case discoverCharacteristics(Service<Peripheral>)
        case readCharacteristic(Characteristic<Peripheral>)
        case writeCharacteristic(Characteristic<Peripheral>)
        case flushWriteWithoutResponse(Peripheral)
        case updateCharacteristicNotificationState(Characteristic<Peripheral>)
        
        var peripheral: Peripheral? {
            switch self {
            case .scan:
                return nil
            case let .connect(peripheral):
                return peripheral
            case let .discoverServices(peripheral):
                return peripheral
            case let .discoverCharacteristics(service):
                return service.peripheral
            case let .readCharacteristic(characteristic):
                return characteristic.peripheral
            case let .writeCharacteristic(characteristic):
                return characteristic.peripheral
            case let .flushWriteWithoutResponse(peripheral):
                return peripheral
            case let .updateCharacteristicNotificationState(characteristic):
                return characteristic.peripheral
            }
        }
    }
    
    struct Cache {
        
        fileprivate init() { }
        
        var services = Services()
        
        struct Services {
            
            fileprivate(set) var values: [UInt: CBService] = [:]
        }
        
        mutating func update(_ newValues: [CBService]) {
            
            newValues.enumerated().forEach {
                let identifier = UInt($0.offset)
                services.values[identifier] = $0.element
            }
        }
        
        var characteristics = Characteristics()
        
        struct Characteristics {
            
            fileprivate(set) var values: [UInt: (attribute: CBCharacteristic, notification: ((Data) -> ())?)] = [:]
        }
        
        mutating func insert(_ newValues: [CBCharacteristic],
                             for service: CBService) {
            guard let serviceIdentifier = services.values.first(where: { $0.value === service })?.key else {
                assertionFailure("Attempted to insert characteristics into cache for unknown service: \(service)")
                return
            }
            
            // remove old characteristics for service
            while let key = characteristics.values
                .first(where: { $0.value.attribute.service === service })?.key {
                characteristics.values[key] = nil
            }
            
            // insert new characteristics
            newValues.enumerated().forEach {
                // Characteristic identifier must be namespaced to service identifier to avoid collisions.
                // A simple solution is to combine the service identifier with the characteristic identifier.
                // To do this, we'll pad the service identifier and then add the characteristic identifier.
                let serviceIdentifierPadding = UInt(10000)
                assert($0.offset < serviceIdentifierPadding)
                
                let characteristicIdentifier = (serviceIdentifier * serviceIdentifierPadding) + UInt($0.offset)
                characteristics.values[characteristicIdentifier] = (attribute: $0.element, notification: nil)
            }
        }
    }
}

internal extension DarwinCentral {
    
    final class Semaphore {
        
        let operation: Operation
        let semaphore: DispatchSemaphore
        let timeout: TimeInterval
        var error: Swift.Error?
        
        init(timeout: TimeInterval,
             operation: Operation) {
            
            self.operation = operation
            self.timeout = timeout
            self.semaphore = DispatchSemaphore(value: 0)
            self.error = nil
        }
        
        func wait() throws {
            
            let dispatchTime: DispatchTime = .now() + timeout
            let success = semaphore.wait(timeout: dispatchTime) == .success
            if let error = self.error {
                throw error
            }
            guard success else { throw CentralError.timeout }
        }
        
        func stopWaiting(_ error: Swift.Error? = nil) {
            
            // store signal
            self.error = error
            
            // stop blocking
            semaphore.signal()
        }
    }
}
    
#endif
