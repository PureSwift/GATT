//
//  DarwinCentral.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/3/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import SwiftFoundation
import Bluetooth

#if os(OSX) || os(iOS) || os(tvOS)
    
    import Foundation
    import CoreBluetooth
    
    /// The platform specific peripheral.
    public typealias CentralManager = DarwinCentral
    
    public final class DarwinCentral: NSObject, NativeCentral, CBCentralManagerDelegate, CBPeripheralDelegate {
        
        public typealias Error = CentralError
        
        // MARK: - Properties
        
        public var log: ((String) -> ())?
        
        #if os(OSX)
        
        public var stateChanged: (CBCentralManagerState) -> () = { _ in }
        
        public var state: CBCentralManagerState {
            
            return internalManager.state
        }
        
        #else
        
        public var stateChanged: (CBCentralManagerState) -> () = { _ in }
        
        public var state: CBCentralManagerState {
        
            return unsafeBitCast(internalManager.state, to: CBCentralManagerState.self)
        }
        
        #endif
        
        public var didDisconnect: (Peripheral) -> () = { _ in }
        
        // MARK: - Private Properties
        
        private lazy var internalManager: CBCentralManager = CBCentralManager(delegate: self, queue: self.queue)
        
        private lazy var queue: DispatchQueue = DispatchQueue(label: "\(type(of: self)) Internal Queue", attributes: [])
        
        private var poweredOnSemaphore: DispatchSemaphore!
        
        private var operationState: (semaphore: DispatchSemaphore, error: Swift.Error?)!
        
        private var scanPeripherals = [CBPeripheral]()
        
        private var isReading = false
        
        private var connectingToPeripheral: CBPeripheral?
        
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
        
        public func scan(duration: Int = 5) -> [Peripheral] {
            
            sync {
                
                self.scanPeripherals = []
                
                self.internalManager.scanForPeripherals(withServices: nil, options: nil)
            }
            
            sleep(UInt32(duration))
            
            return sync {
                
                self.internalManager.stopScan()
                
                return self.scanPeripherals.map { Peripheral($0) }
            }
        }
 
        public func connect(to peripheral: Peripheral, timeout: Int = 5) throws {
            
            try sync {
                
                guard let corePeripheral = self.peripheral(peripheral)
                    else { throw CentralError.unknownPeripheral }
                
                self.connectingToPeripheral = corePeripheral
                
                self.internalManager.connect(corePeripheral, options: nil)
            }
            
            var success = true
            
            do { success = try wait(timeout) }
                
            catch {
                
                sync { self.connectingToPeripheral = nil }
                
                throw error
            }
            
            // no error
            sync { self.connectingToPeripheral = nil }
            
            guard success else { throw CentralError.timeout }
            
            assert(sync { self.peripheral(peripheral)!.state != .disconnected })
        }
        
        public func disconnect(peripheral: Peripheral) {
            
            guard let corePeripheral = self.peripheral(peripheral)
                else { return }
            
            internalManager.cancelPeripheralConnection(corePeripheral)
        }
        
        public func disconnectAll() {
            
            for peripheral in scanPeripherals {
                
                internalManager.cancelPeripheralConnection(peripheral)
            }
        }
        
        public func discoverServices(for peripheral: Peripheral) throws -> [(UUID: BluetoothUUID, primary: Bool)] {
            
            let corePeripheral: CBPeripheral = try sync {
                
                guard let corePeripheral = self.peripheral(peripheral)
                    else { throw CentralError.disconnected }
                
                guard corePeripheral.state == .connected
                    else { throw CentralError.disconnected }
                
                corePeripheral.discoverServices(nil)
                
                return corePeripheral
            }
            
            let _ = try wait()
            
            return sync { (corePeripheral.services ?? []).map { (BluetoothUUID(coreBluetooth: $0.uuid), $0.isPrimary) } }
        }
        
        public func discoverCharacteristics(for service: BluetoothUUID, peripheral: Peripheral) throws -> [(UUID: BluetoothUUID, properties: [Characteristic.Property])] {
            
            guard let corePeripheral = self.peripheral(peripheral)
                else { throw CentralError.disconnected }
            
            guard corePeripheral.state == .connected
                else { throw CentralError.disconnected }
            
            let coreService = corePeripheral.service(service)
            
            corePeripheral.discoverCharacteristics(nil, for: coreService)
            
            let _ = try wait()
            
            return (coreService.characteristics ?? []).map { (BluetoothUUID(coreBluetooth: $0.uuid), Characteristic.Property.from(CoreBluetooth: $0.properties)) }
        }
        
        public func read(characteristic UUID: BluetoothUUID, service: BluetoothUUID, peripheral: Peripheral) throws -> Data {
            
            guard let corePeripheral = self.peripheral(peripheral)
                else { throw CentralError.disconnected }
            
            guard corePeripheral.state == .connected
                else { throw CentralError.disconnected }
            
            let coreService = corePeripheral.service(service)
            
            let coreCharacteristic = coreService.characteristic(UUID)
            
            corePeripheral.readValue(for: coreCharacteristic)
            
            isReading = true
            
            let _ = try wait()
            
            isReading = false
            
            return coreCharacteristic.value ?? Data()
        }
        
        public func write(data: Data, response: Bool, characteristic UUID: BluetoothUUID, service: BluetoothUUID, peripheral: Peripheral) throws {
            
            guard let corePeripheral = self.peripheral(peripheral)
                else { throw CentralError.disconnected }
            
            guard corePeripheral.state == .connected
                else { throw CentralError.disconnected }
            
            let coreService = corePeripheral.service(service)
            
            let coreCharacteristic = coreService.characteristic(UUID)
            
            let writeType: CBCharacteristicWriteType = response ? .withResponse : .withoutResponse
            
            corePeripheral.writeValue(data, for: coreCharacteristic, type: writeType)
            
            if response {
                
                let _ = try wait()
            }
        }
 
        // MARK: - Private Methods
        
        private func peripheral(_ peripheral: Peripheral) -> CBPeripheral? {
            
            for foundPeripheral in scanPeripherals {
                
                guard foundPeripheral.identifier != peripheral.identifier
                    else { return foundPeripheral }
            }
            
            return nil
        }
        
        private func wait(_ timeout: Int? = nil) throws -> Bool {
            
            assert(operationState == nil, "Already waiting for an asyncronous operation to finish")
            
            let semaphore = DispatchSemaphore(value: 0)
            
            // set semaphore
            operationState = (semaphore, nil)
            
            // wait
            
            let dispatchTime: DispatchTime
            
            if let timeout = timeout {
                
                dispatchTime = DispatchTime.now() + Double(timeout)
                
            } else {
                
                dispatchTime = .distantFuture
            }
            
            let success = semaphore.wait(timeout: dispatchTime) == .success
            
            let error = operationState.error
            
            // clear state
            operationState = nil
            
            if let error = error {
                
                throw error
            }
            
            return success
        }
        
        private func stopWaiting(_ error: Swift.Error? = nil, _ function: String = #function) {
            
            assert(operationState != nil, "Did not expect \(function)")
            
            operationState.error = error
            
            operationState.semaphore.signal()
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
        public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
            
            log?("Did discover peripheral \(peripheral)")
            
            if peripheral.delegate == nil {
                
                peripheral.delegate = self
            }
            
            if scanPeripherals.contains(peripheral) == false {
                
                scanPeripherals.append(peripheral)
            }
        }
        
        @objc(centralManager:didConnectPeripheral:)
        public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
            
            log?("Connecting to peripheral \(peripheral.identifier.uuidString)")
            
            if connectingToPeripheral === peripheral {
                
                assert(peripheral.state != .disconnected)
                
                stopWaiting()
            }
        }
        
        @objc(centralManager:didFailToConnectPeripheral:error:)
        public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Swift.Error?) {
            
            //log?("Did fail to connect to peripheral \(peripheral.identifier.uuidString) (\(error!))")
            
            if connectingToPeripheral?.identifier == peripheral.identifier {
                
                stopWaiting(error)
            }
        }
        
        @objc(centralManager:didDisconnectPeripheral:error:)
        public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Swift.Error?) {
            
            self.didDisconnect(Peripheral(peripheral))
        }
        
        // MARK: - CBPeripheralDelegate
        
        @objc(peripheral:didDiscoverServices:)
        public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Swift.Error?) {
            
            if let error = error {
                
                log?("Error discovering services (\(error))")
                
            } else {
                
                log?("Peripheral \(peripheral.identifier.uuidString) did discover \(peripheral.services?.count ?? 0) services")
            }
            
             stopWaiting(error)
        }
        
        @objc(peripheral:didDiscoverCharacteristicsForService:error:)
        public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Swift.Error?) {
            
            if let error = error {
                
                log?("Error discovering characteristics (\(error))")
                
            } else {
                
                log?("Peripheral \(peripheral.identifier.uuidString) did discover \(service.characteristics?.count ?? 0) characteristics for service \(service.uuid.uuidString)")
            }
            
            stopWaiting(error)
        }
        
        @objc(peripheral:didUpdateValueForCharacteristic:error:)
        public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Swift.Error?) {
            
            if let error = error {
                
                log?("Error reading characteristic (\(error))")
                
            } else {
                
                log?("Peripheral \(peripheral.identifier.uuidString) did update value for characteristic \(characteristic.uuid.uuidString)")
            }
            
            if isReading {
                
                stopWaiting(error)
            }
        }
 
        @objc(peripheral:didWriteValueForCharacteristic:error:)
        public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Swift.Error?) {
            
            if let error = error {
                
                log?("Error writing characteristic (\(error))")
                
            } else {
                
                log?("Peripheral \(peripheral.identifier.uuidString) did write value for characteristic \(characteristic.uuid.uuidString)")
            }
            
            stopWaiting(error)
        }
    }
    
    private extension CBPeripheral {
        
        func service(_ UUID: BluetoothUUID) -> CBService {
            
            for service in services ?? [] {
                
                guard service.uuid != UUID.toCoreBluetooth()
                    else { return service }
            }
            
            fatalError("Service \(UUID) not found")
        }
    }
    
    private extension CBService {
        
        func characteristic(_ UUID: BluetoothUUID) -> CBCharacteristic {
            
            for characteristic in characteristics ?? [] {
                
                guard characteristic.uuid != UUID.toCoreBluetooth()
                    else { return characteristic }
            }
            
            fatalError("Characteristic \(UUID) not found")
        }
    }
    
#endif
