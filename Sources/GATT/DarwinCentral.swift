//
//  DarwinCentral.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/3/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import Foundation
import Bluetooth

#if os(macOS) || os(iOS) || os(tvOS) || (os(watchOS) && swift(>=3.2))
    
    import Foundation
    import CoreBluetooth
    
    /// The platform specific peripheral.

    public typealias CentralManager = DarwinCentral
    
    @objc

    public final class DarwinCentral: NSObject, NativeCentral, CBCentralManagerDelegate, CBPeripheralDelegate {
        
        // MARK: - Properties
        
        public var log: ((String) -> ())?
        
        public var stateChanged: (DarwinBluetoothState) -> () = { _ in }
        
        public var state: DarwinBluetoothState {
            
            return unsafeBitCast(internalManager.state, to: DarwinBluetoothState.self)
        }
        
        public var isScanning: Bool {
            
            if #available(OSX 10.13, iOS 9.0, *) {
                return internalManager.isScanning
            } else {
                return accessQueue.sync { [unowned self] in self.internalState.scan.foundDevice != nil }
            }
        }
        
        public var didDisconnect: (Peripheral) -> () = { _ in }
        
        // MARK: - Private Properties
        
        internal lazy var internalManager: CBCentralManager = CBCentralManager(delegate: self, queue: self.managerQueue)
        
        internal lazy var managerQueue: DispatchQueue = DispatchQueue(label: "\(type(of: self)) Manager Queue", attributes: [])
        
        internal lazy var accessQueue: DispatchQueue = DispatchQueue(label: "\(type(of: self)) Access Queue", attributes: [])
        
        internal private(set) var internalState = InternalState()
        
        private var notifications = [Peripheral: [BluetoothUUID: (Data) -> ()]]()
        
        // MARK: - Methods
        
        public func scan(filterDuplicates: Bool = true,
                         shouldContinueScanning: () -> (Bool),
                         foundDevice: @escaping (ScanData) -> ()) {
            
            let options: [String: Any] = [
                CBCentralManagerScanOptionAllowDuplicatesKey: NSNumber(value: filterDuplicates == false)
            ]
            
            accessQueue.sync { [unowned self] in
                
                self.internalState.scan.peripherals = [:]
                self.internalState.scan.foundDevice = foundDevice
            }
            
            self.internalManager.scanForPeripherals(withServices: nil, options: options)
            
            // sleep until scan finishes
            while shouldContinueScanning() { usleep(100) }
            
            self.internalManager.stopScan()
            
            accessQueue.sync { [unowned self] in
                
                self.internalState.scan.foundDevice = nil
            }
        }
        
        public func connect(to peripheral: Peripheral, timeout: TimeInterval) throws {
            
            try connect(to: peripheral, timeout: timeout)
        }
 
        /// A dictionary to customize the behavior of the connection. For available options, see [Peripheral Connection Options](apple-reference-documentation://ts1667676).
        public func connect(to peripheral: Peripheral, timeout: TimeInterval, options: [String: Any]) throws {
            
            guard let corePeripheral = accessQueue.sync(execute: { [unowned self] in self.peripheral(peripheral) })
                else { throw CentralError.unknownPeripheral }
            
            let semaphore = Semaphore(timeout: timeout, operation: .connect(peripheral))
            
            // store semaphore
            accessQueue.sync { [unowned self] in self.internalState.connect.semaphore = semaphore }
            
            defer { accessQueue.sync { [unowned self] in self.internalState.connect.semaphore = nil } }
            
            // attempt to connect (does not timeout)
            self.internalManager.connect(corePeripheral, options: options)
            
            assert(corePeripheral.state == .connecting, "Peripheral should be connecting")
            
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
            
            accessQueue.sync(execute: { [unowned self] in
             
                self.internalState.scan.peripherals.values.forEach { [unowned self] in
                    self.internalManager.cancelPeripheralConnection($0.peripheral)
                }
            }
        }
        
        public func discoverServices(for peripheral: Peripheral) throws -> [Service] {
            
            let corePeripheral = try connectedPeriperhal(peripheral)
            
            try wait(.discoverServices(peripheral)) {
                corePeripheral.discoverServices(nil)
            }
            
            return (corePeripheral.services ?? []).map {
                Service(
                    uuid: BluetoothUUID(coreBluetooth: $0.uuid),
                    isPrimary: $0.isPrimary)
            }
        }
        
        public func discoverCharacteristics(for service: BluetoothUUID,
                                            peripheral: Peripheral) throws -> [Characteristic] {
            
            let corePeripheral = try connectedPeriperhal(peripheral)
            
            let coreService = try corePeripheral.service(service)
            
            try wait(.discoverCharacteristics(peripheral, service)) {
                corePeripheral.discoverCharacteristics(nil, for: coreService)
            }
            
            return (coreService.characteristics ?? [])
                .map { Characteristic(uuid: BluetoothUUID(coreBluetooth: $0.uuid),
                                      properties: Characteristic.Property.from(coreBluetooth: $0.properties)) }
        }
        
        public func read(characteristic: BluetoothUUID,
                         service: BluetoothUUID,
                         peripheral: Peripheral) throws -> Data {
            
            let corePeripheral = try connectedPeriperhal(peripheral)
            
            let coreService = try corePeripheral.service(service)
            
            let coreCharacteristic = try coreService.characteristic(characteristic)
            
            try wait(.readCharacteristic(peripheral, service, characteristic)) {
                
                corePeripheral.readValue(for: coreCharacteristic)
            }
            
            return coreCharacteristic.value ?? Data()
        }
        
        public func write(data: Data,
                          response: Bool,
                          characteristic: BluetoothUUID,
                          service: BluetoothUUID,
                          peripheral: Peripheral) throws {
            
            let corePeripheral = try connectedPeriperhal(peripheral)
            
            let coreService = try corePeripheral.service(service)
            
            let coreCharacteristic = try coreService.characteristic(characteristic)
            
            let writeType: CBCharacteristicWriteType = response ? .withResponse : .withoutResponse
            
            if response {
                
                try wait(.writeCharacteristic(peripheral, service, characteristic)) {
                    
                    corePeripheral.writeValue(data, for: coreCharacteristic, type: writeType)
                }
                
            } else {
                
                corePeripheral.writeValue(data, for: coreCharacteristic, type: writeType)
            }
        }
        
        public func notify(characteristic: BluetoothUUID,
                           service: BluetoothUUID,
                           peripheral: Peripheral,
                           notification: ((Data) -> ())?) throws {
            
            let corePeripheral = try connectedPeriperhal(peripheral)
            
            let coreService = try corePeripheral.service(service)
            
            let coreCharacteristic = try coreService.characteristic(characteristic)
            
            let isEnabled = notification != nil
            
            try wait(.updateCharacteristicNotificationState(peripheral, service, characteristic))  {
                
                corePeripheral.setNotifyValue(isEnabled, for: coreCharacteristic)
            }
            
            #if swift(>=3.2)
            notifications[peripheral, default: [:]][characteristic] = notification
            #elseif swift(>=3.0)
            var newValue = notifications[peripheral] ?? [:]
            newValue[characteristic] = notification
            notifications[peripheral] = newValue
            #endif
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
            
            log?("Did update state (\(central.state == .poweredOn ? "Powered On" : "\(central.state.rawValue)"))")
            
            stateChanged(unsafeBitCast(central.state, to: DarwinBluetoothState.self))
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
            
            let scanResult = ScanData(date: Date(),
                                      peripheral: identifier,
                                      rssi: rssi.doubleValue,
                                      advertisementData: AdvertisementData(advertisementData))
            
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
        public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Swift.Error?) {
            
            self.didDisconnect(Peripheral(peripheral))
        }
        
        // MARK: - CBPeripheralDelegate
        
        @objc(peripheral:didDiscoverServices:)
        public func peripheral(_ corePeripheral: CBPeripheral, didDiscoverServices error: Swift.Error?) {
            
            if let error = error {
                
                log?("Error discovering services (\(error))")
                
            } else {
                
                log?("Peripheral \(corePeripheral.gattIdentifier.uuidString) did discover \(corePeripheral.services?.count ?? 0) services")
            }
            
            guard let operation = operationState?.operation,
                case let .discoverServices(peripheral) = operation,
                peripheral == Peripheral(corePeripheral)
                else { return }
            
            stopWaiting(error)
        }
        
        @objc(peripheral:didDiscoverCharacteristicsForService:error:)
        public func peripheral(_ corePeripheral: CBPeripheral, didDiscoverCharacteristicsFor coreService: CBService, error: Swift.Error?) {
            
            if let error = error {
                
                log?("Error discovering characteristics (\(error))")
                
            } else {
                
                log?("Peripheral \(corePeripheral.gattIdentifier.uuidString) did discover \(coreService.characteristics?.count ?? 0) characteristics for service \(coreService.uuid.uuidString)")
            }
            
            guard let operation = operationState?.operation,
                case let .discoverCharacteristics(peripheral, service) = operation,
                peripheral == Peripheral(corePeripheral),
                service == BluetoothUUID(coreBluetooth: coreService.uuid)
                else { assertionFailure("Unexpected \(#function)"); return }
            
            stopWaiting(error)
        }
        
        @objc(peripheral:didUpdateValueForCharacteristic:error:)
        public func peripheral(_ corePeripheral: CBPeripheral, didUpdateValueFor coreCharacteristic: CBCharacteristic, error: Swift.Error?) {
            
            if let error = error {
                
                log?("Error reading characteristic (\(error))")
                
            } else {
                
                log?("Peripheral \(corePeripheral.gattIdentifier.uuidString) did update value for characteristic \(coreCharacteristic.uuid.uuidString)")
            }
            
            if let operation = operationState?.operation,
                case let .readCharacteristic(peripheral, service, characteristic) = operation,
                peripheral == Peripheral(corePeripheral),
                service == BluetoothUUID(coreBluetooth: coreCharacteristic.service.uuid),
                characteristic == BluetoothUUID(coreBluetooth: coreCharacteristic.uuid) {
                
                stopWaiting(error)
                
            } else {
                
                assert(error == nil)
                
                let uuid = BluetoothUUID(coreBluetooth: coreCharacteristic.uuid)
                
                let data = coreCharacteristic.value ?? Data()
                
                guard let peripheralNotifications = notifications[Peripheral(corePeripheral)],
                    let notification = peripheralNotifications[uuid]
                    else { assertionFailure("Unexpected notification for \(coreCharacteristic.uuid)"); return }
                
                // notify
                notification(data)
            }
        }
 
        @objc(peripheral:didWriteValueForCharacteristic:error:)
        public func peripheral(_ corePeripheral: CBPeripheral, didWriteValueFor coreCharacteristic: CBCharacteristic, error: Swift.Error?) {
            
            if let error = error {
                
                log?("Error writing characteristic (\(error))")
                
            } else {
                
                log?("Peripheral \(corePeripheral.gattIdentifier.uuidString) did write value for characteristic \(coreCharacteristic.uuid.uuidString)")
            }
            
            guard let operation = operationState?.operation,
                case let .writeCharacteristic(peripheral, service, characteristic) = operation,
                peripheral == Peripheral(corePeripheral),
                service == BluetoothUUID(coreBluetooth: coreCharacteristic.service.uuid),
                characteristic == BluetoothUUID(coreBluetooth: coreCharacteristic.uuid)
                else { return }
            
            stopWaiting(error)
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
            
            guard let operation = operationState?.operation,
                case let .updateCharacteristicNotificationState(peripheral, service, characteristic) = operation,
                peripheral == Peripheral(corePeripheral),
                service == BluetoothUUID(coreBluetooth: coreCharacteristic.service.uuid),
                characteristic == BluetoothUUID(coreBluetooth: coreCharacteristic.uuid)
                else { return }
            
            stopWaiting(error)
        }
        
        @objc(peripheral:didUpdateValueForDescriptor:error:)
        public func peripheral(_ peripheral: CBPeripheral,
                               didUpdateValueFor descriptor: CBDescriptor,
                               error: Swift.Error?) {
            
            // TODO: Descriptor notifications
        }
    }
    

    internal extension DarwinCentral {
        
        struct InternalState {
            
            fileprivate init() { }
            
            var scan = Scan()
            
            struct Scan {
                
                var peripherals = [Peripheral: (peripheral: CBPeripheral, scanResult: ScanData)]()
                
                var foundDevice: ((ScanData) -> ())?
            }
            
            var connect: Connect
            
            struct Connect {
                
                var semaphore: Semaphore?
            }
        }
        
        enum Operation {
            
            case connect(Peripheral)
            case discoverServices(Peripheral)
            case discoverCharacteristics(Peripheral, BluetoothUUID)
            case readCharacteristic(Peripheral, BluetoothUUID, BluetoothUUID)
            case writeCharacteristic(Peripheral, BluetoothUUID, BluetoothUUID)
            case updateCharacteristicNotificationState(Peripheral, BluetoothUUID, BluetoothUUID)
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
    
    private extension CBPeripheral {
        
        func service(_ uuid: BluetoothUUID) throws -> CBService {
            
            guard let service = services?.first(where: { $0.uuid == uuid.toCoreBluetooth() })
                else { throw CentralError.invalidAttribute(uuid) }
            
            return service
        }
    }
    
    private extension CBService {
        
        func characteristic(_ uuid: BluetoothUUID) throws -> CBCharacteristic {
            
            guard let characteristic = characteristics?.first(where: { $0.uuid == uuid.toCoreBluetooth() })
                else { throw CentralError.invalidAttribute(uuid) }
            
            return characteristic
        }
    }
    
#endif
