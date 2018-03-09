//
//  DarwinCentral.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/3/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import Foundation
import Bluetooth

#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
    
    import Foundation
    import CoreBluetooth
    
    /// The platform specific peripheral.
    public typealias CentralManager = DarwinCentral
    
    @objc
    public final class DarwinCentral: NSObject, NativeCentral, CBCentralManagerDelegate, CBPeripheralDelegate {
        
        public typealias Error = CentralError
        
        // MARK: - Properties
        
        public var log: ((String) -> ())?
        
        public var stateChanged: (CBCentralManagerState) -> () = { _ in }
        
        public var state: CBCentralManagerState {
            
            return unsafeBitCast(internalManager.state, to: CBCentralManagerState.self)
        }
        
        public var didDisconnect: (Peripheral) -> () = { _ in }
        
        // MARK: - Private Properties
        
        private lazy var internalManager: CBCentralManager = CBCentralManager(delegate: self, queue: self.queue)
        
        private lazy var queue: DispatchQueue = DispatchQueue(label: "\(type(of: self)) Queue", attributes: [])
        
        private var poweredOnSemaphore: DispatchSemaphore!
        
        private var operationState: OperationState?
        
        private var scanPeripherals = [Peripheral: (peripheral: CBPeripheral, scanResult: ScanData)]()
        
        private var foundDevice: ((ScanData) -> ())?
        
        private var notifications = [Peripheral: [BluetoothUUID: (Data) -> ()]]()
        
        // MARK: - Methods
        
        public func waitForPoweredOn() {
            
            // already on
            guard internalManager.state != .poweredOn else { return }
            
            // already waiting
            guard poweredOnSemaphore == nil else { let _ = poweredOnSemaphore.wait(timeout: .distantFuture); return }
            
            log?("Not powered on (State \(internalManager.state.rawValue))")
            
            poweredOnSemaphore = DispatchSemaphore(value: 0)
            
            let _ = poweredOnSemaphore.wait(timeout: .distantFuture)
            
            poweredOnSemaphore = nil
            
            assert(internalManager.state == .poweredOn)
            
            log?("Now powered on")
        }
        
        public func scan(filterDuplicates: Bool = false,
                         shouldContinueScanning: () -> (Bool),
                         foundDevice: @escaping (ScanData) -> ()) {
            
            let options: [String: Any] = [
                CBCentralManagerScanOptionAllowDuplicatesKey: NSNumber(value: filterDuplicates == false)
            ]
            
            self.scanPeripherals = [:]
            
            self.foundDevice = foundDevice
            
            self.internalManager.scanForPeripherals(withServices: nil, options: options)
            
            // sleep until scan finishes
            while shouldContinueScanning() { usleep(100) }
            
            self.internalManager.stopScan()
            
            self.foundDevice = nil
        }
 
        public func connect(to peripheral: Peripheral, timeout: Int = 5) throws {
            
            try sync {
                
                guard let corePeripheral = self.peripheral(peripheral)
                    else { throw CentralError.unknownPeripheral }
                
                self.internalManager.connect(corePeripheral, options: nil)
            }
            
            try wait(.connect(peripheral), timeout) { }
            
            assert(self.peripheral(peripheral)!.state != .disconnected)
        }
        
        public func disconnect(peripheral: Peripheral) {
            
            guard let corePeripheral = self.peripheral(peripheral)
                else { return }
            
            internalManager.cancelPeripheralConnection(corePeripheral)
        }
        
        public func disconnectAll() {
            
            for (peripheral: peripheral, scanResult: _) in scanPeripherals.values {
                
                internalManager.cancelPeripheralConnection(peripheral)
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
            
            notifications[peripheral, default: [:]][characteristic] = notification
        }
        
        // MARK: - Private Methods
        
        private func peripheral(_ peripheral: Peripheral) -> CBPeripheral? {
            
            return scanPeripherals[peripheral]?.peripheral
        }
        
        private func connectedPeriperhal(_ peripheral: Peripheral) throws -> CBPeripheral {
            
            guard let corePeripheral = self.peripheral(peripheral)
                else { throw CentralError.unknownPeripheral }
            
            guard corePeripheral.state == .connected
                else { throw CentralError.disconnected }
            
            return corePeripheral
        }
        
        private func wait(_ operation: Operation, _ timeout: Int? = nil, action: () -> ()) throws {
            
            assert(operationState == nil, "Already waiting for an asyncronous operation to finish")
            
            let semaphore = DispatchSemaphore(value: 0)
            
            // set semaphore
            operationState = OperationState(operation: operation,
                                            semaphore: semaphore,
                                            error: nil)
            
            // wait
            
            let dispatchTime: DispatchTime
            
            if let timeout = timeout {
                
                dispatchTime = DispatchTime.now() + Double(timeout)
                
            } else {
                
                dispatchTime = .distantFuture
            }
            
            log?("Waiting for operation \(operationState!.operation)")
            
            action()
            
            let success = semaphore.wait(timeout: dispatchTime) == .success
            
            let error = operationState?.error
            
            // clear state
            operationState = nil
            
            if let error = error {
                
                throw error
            }
            
            guard success else { throw CentralError.timeout }
        }
        
        private func stopWaiting(_ error: Swift.Error? = nil, _ function: String = #function) {
            
            guard let semaphore = self.operationState?.semaphore
                else { assertionFailure("Did not expect \(function)"); return }
            
            // store signal
            self.operationState?.error = error
            
            // stop blocking
            semaphore.signal()
        }
        
        /// Perform a task on the internal queue and wait. Can throw error.
        private func sync<T>(_ block: () throws -> T) throws -> T {
            
            var blockValue: T!
            
            var caughtError: Swift.Error?
            
            queue.sync {
                
                do { blockValue = try block() }
                    
                catch { caughtError = error }
            }
            
            if let error = caughtError {
                
                throw error
            }
            
            return blockValue
        }
        
        /// Perform a task on the internal queue and wait.
        private func sync<T>(_ block: () -> T) -> T {
            
            var blockValue: T!
            
            queue.sync { blockValue = block() }
            
            return blockValue
        }
 
        // MARK: - CBCentralManagerDelegate
        
        @objc(centralManagerDidUpdateState:)
        public func centralManagerDidUpdateState(_ central: CBCentralManager) {
            
            log?("Did update state (\(central.state == .poweredOn ? "Powered On" : "\(central.state.rawValue)"))")
            
            stateChanged(unsafeBitCast(central.state, to: CBCentralManagerState.self))
            
            if central.state == .poweredOn && poweredOnSemaphore != nil {
                
                poweredOnSemaphore.signal()
            }
        }
        
        @objc(centralManager:didDiscoverPeripheral:advertisementData:RSSI:)
        public func centralManager(_ central: CBCentralManager,
                                   didDiscover peripheral: CBPeripheral,
                                   advertisementData: [String : Any],
                                   rssi: NSNumber) {
            
            log?("Did discover peripheral \(peripheral)")
            
            if peripheral.delegate == nil {
                
                peripheral.delegate = self
            }
            
            let identifier = Peripheral(peripheral)
            
            let scanResult = ScanData(date: Date(),
                                        peripheral: identifier,
                                        rssi: rssi.doubleValue,
                                        advertisementData: AdvertisementData(advertisementData))
            
            scanPeripherals[identifier] = (peripheral, scanResult)
            
            foundDevice?(scanResult)
        }
        
        @objc(centralManager:didConnectPeripheral:)
        public func centralManager(_ central: CBCentralManager, didConnect corePeripheral: CBPeripheral) {
            
            log?("Connecting to peripheral \(corePeripheral.identifier.uuidString)")
            
            guard let operation = operationState?.operation,
                case let .connect(peripheral) = operation,
                peripheral == Peripheral(corePeripheral)
                else { return }
            
            assert(corePeripheral.state != .disconnected, "Should be connected")
            
            stopWaiting()
        }
        
        @objc(centralManager:didFailToConnectPeripheral:error:)
        public func centralManager(_ central: CBCentralManager, didFailToConnect corePeripheral: CBPeripheral, error: Swift.Error?) {
            
            log?("Did fail to connect to peripheral \(corePeripheral.identifier.uuidString) (\(error!))")
            
            guard let operation = operationState?.operation,
                case let .connect(peripheral) = operation,
                peripheral == Peripheral(corePeripheral)
                else { return }
            
            stopWaiting(error)
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
                
                log?("Peripheral \(corePeripheral.identifier.uuidString) did discover \(corePeripheral.services?.count ?? 0) services")
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
                
                log?("Peripheral \(corePeripheral.identifier.uuidString) did discover \(coreService.characteristics?.count ?? 0) characteristics for service \(coreService.uuid.uuidString)")
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
                
                log?("Peripheral \(corePeripheral.identifier.uuidString) did update value for characteristic \(coreCharacteristic.uuid.uuidString)")
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
                
                log?("Peripheral \(corePeripheral.identifier.uuidString) did write value for characteristic \(coreCharacteristic.uuid.uuidString)")
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
                
                log?("Peripheral \(corePeripheral.identifier.uuidString) did update notification state for characteristic \(coreCharacteristic.uuid.uuidString)")
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
    
    private extension DarwinCentral {
        
        enum Operation {
            
            case connect(Peripheral)
            case discoverServices(Peripheral)
            case discoverCharacteristics(Peripheral, BluetoothUUID)
            case readCharacteristic(Peripheral, BluetoothUUID, BluetoothUUID)
            case writeCharacteristic(Peripheral, BluetoothUUID, BluetoothUUID)
            case updateCharacteristicNotificationState(Peripheral, BluetoothUUID, BluetoothUUID)
        }
        
        struct OperationState {
            
            let operation: Operation
            let semaphore: DispatchSemaphore
            var error: Swift.Error?
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
