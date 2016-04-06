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
        
        public var log: (String -> ())?
        
        public var stateChanged: (CBCentralManagerState) -> () = { _ in }
        
        public var state: CBCentralManagerState {
            
            return internalManager.state
        }
        
        // MARK: - Private Properties
        
        private lazy var internalManager: CBCentralManager = CBCentralManager(delegate: self, queue: self.queue)
        
        private lazy var queue: dispatch_queue_t = dispatch_queue_create("\(self.dynamicType) Internal Queue", nil)
        
        private var poweredOnSemaphore: dispatch_semaphore_t!
        
        private var operationState: (semaphore: dispatch_semaphore_t, error: NSError?)!
        
        private var scanPeripherals = [CBPeripheral]()
        
        private var isReading = false
        
        private var connectingToPeripheral: CBPeripheral?
        
        // MARK: - Methods
        
        public func waitForPoweredOn() {
            
            // already on
            guard internalManager.state != .poweredOn else { return }
            
            // already waiting
            guard poweredOnSemaphore == nil else { dispatch_semaphore_wait(poweredOnSemaphore, DISPATCH_TIME_FOREVER); return }
            
            log?("Not powered on (State \(internalManager.state.rawValue))")
            
            poweredOnSemaphore = dispatch_semaphore_create(0)
            
            dispatch_semaphore_wait(poweredOnSemaphore, DISPATCH_TIME_FOREVER)
            
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
        
        public func connect(peripheral: Peripheral, timeout: Int = 5) throws {
            
            sync {
                
                let corePeripheral = self.peripheral(peripheral)
                
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
            
            guard success else { throw Error.Timeout }
            
            assert(sync { self.peripheral(peripheral).state != .disconnected })
        }
        
        public func discover(services peripheral: Peripheral) throws -> [(UUID: Bluetooth.UUID, primary: Bool)] {
            
            let corePeripheral: CBPeripheral = sync {
                
                let corePeripheral = self.peripheral(peripheral)
                
                assert(corePeripheral.state == .connected)
                
                corePeripheral.discoverServices(nil)
                
                return corePeripheral
            }
            
            try wait()
            
            return sync { (corePeripheral.services ?? []).map { (Bluetooth.UUID(foundation: $0.uuid), $0.isPrimary) } }
        }
        
        public func discover(characteristics service: Bluetooth.UUID, peripheral: Peripheral) throws -> [(UUID: Bluetooth.UUID, properties: [Characteristic.Property])] {
            
            let corePeripheral = self.peripheral(peripheral)
            
            let coreService = corePeripheral.service(service)
            
            corePeripheral.discoverCharacteristics(nil, for: coreService)
            
            try wait()
            
            return (coreService.characteristics ?? []).map { (Bluetooth.UUID(foundation: $0.uuid), Characteristic.Property.from($0.properties)) }
        }
        
        public func read(characteristic UUID: Bluetooth.UUID, service: Bluetooth.UUID, peripheral: Peripheral) throws -> Data {
            
            let corePeripheral = self.peripheral(peripheral)
            
            let coreService = corePeripheral.service(service)
            
            let coreCharacteristic = coreService.characteristic(UUID)
            
            corePeripheral.readValue(for: coreCharacteristic)
            
            isReading = true
            
            try wait()
            
            isReading = false
            
            return Data(foundation: coreCharacteristic.value ?? NSData())
        }
        
        // MARK: - Private Methods
        
        private func peripheral(peripheral: Peripheral) -> CBPeripheral {
            
            for foundPeripheral in scanPeripherals {
                
                guard foundPeripheral.identifier != peripheral.identifier.toFoundation()
                    else { return foundPeripheral }
            }
            
            fatalError("\(peripheral) not found")
        }
        
        private func wait(timeout: Int? = nil) throws -> Bool {
            
            assert(operationState == nil, "Already waiting for an asyncronous operation to finish")
            
            let semaphore = dispatch_semaphore_create(0)
            
            // set semaphore
            operationState = (semaphore, nil)
            
            // wait
            
            let dispatchTime: dispatch_time_t
            
            if let timeout = timeout {
                
                dispatchTime = dispatch_time(DISPATCH_TIME_NOW, Int64(timeout) * Int64(NSEC_PER_SEC))
                
            } else {
                
                dispatchTime = DISPATCH_TIME_FOREVER
            }
            
            let success = dispatch_semaphore_wait(semaphore, dispatchTime) == 0
            
            let error = operationState.error
            
            // clear state
            operationState = nil
            
            if let error = error {
                
                throw error
            }
            
            return success
        }
        
        private func stopWaiting(error: NSError? = nil, _ function: String = #function) {
            
            assert(operationState != nil, "Did not expect \(function)")
            
            operationState.error = error
            
            dispatch_semaphore_signal(operationState.semaphore)
        }
        
        /// Perform a task on the internal queue and wait. Can throw error.
        private func sync<T>(block: () throws -> T) throws -> T {
            
            var blockValue: T!
            
            var caughtError: ErrorProtocol?
            
            dispatch_sync(queue) {
                
                do { blockValue = try block() }
                
                catch { caughtError = error }
            }
            
            if let error = caughtError {
                
                throw error
            }
            
            return blockValue
        }
        
        /// Perform a task on the internal queue and wait.
        private func sync<T>(block: () -> T) -> T {
            
            var blockValue: T!
            
            dispatch_sync(queue) { blockValue = block() }
            
            return blockValue
        }
        
        // MARK: - CBCentralManagerDelegate
        
        public func centralManagerDidUpdateState(central: CBCentralManager) {
            
            log?("Did update state (\(central.state == .poweredOn ? "Powered On" : "\(central.state.rawValue)"))")
            
            if central.state == .poweredOn && poweredOnSemaphore != nil {
                
                dispatch_semaphore_signal(poweredOnSemaphore)
            }
        }
        
        public func centralManager(central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : AnyObject], rssi RSSI: NSNumber) {
            
            log?("Did discover peripheral \(peripheral)")
            
            if peripheral.delegate == nil {
                
                peripheral.delegate = self
            }
            
            if scanPeripherals.contains(peripheral) == false {
                
                scanPeripherals.append(peripheral)
            }
        }
        
        public func centralManager(central: CBCentralManager, didConnect peripheral: CBPeripheral) {
            
            log?("Connecting to peripheral \(peripheral.identifier.uuidString)")
            
            if connectingToPeripheral === peripheral {
                
                assert(peripheral.state != .disconnected)
                                
                stopWaiting()
            }
        }
        
        public func centralManager(central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: NSError?) {
            
            log?("Did fail to connect to peripheral \(peripheral.identifier.uuidString) (\(error!))")
            
            if connectingToPeripheral?.identifier == peripheral.identifier {
                
                stopWaiting(error)
            }
        }
        
        // MARK: - CBPeripheralDelegate
        
        public func peripheral(peripheral: CBPeripheral, didDiscoverServices error: NSError?) {
            
            if let error = error {
                
                log?("Error discovering services (\(error))")
                
            } else {
                
                log?("Peripheral \(peripheral.identifier.uuidString) did discover \(peripheral.services?.count ?? 0) services")
            }
            
            stopWaiting(error)
        }
        
        public func peripheral(peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: NSError?) {
            
            if let error = error {
                
                log?("Error discovering characteristics (\(error))")
                
            } else {
                
                log?("Peripheral \(peripheral.identifier.uuidString) did discover \(service.characteristics?.count ?? 0) characteristics for service \(service.uuid.uuidString)")
            }
            
            stopWaiting(error)
        }
        
        public func peripheral(peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: NSError?) {
            
            if let error = error {
                
                log?("Error reading characteristic (\(error))")
                
            } else {
                
                log?("Peripheral \(peripheral.identifier.uuidString) did update value for characteristic \(characteristic.uuid.uuidString)")
            }
            
            if isReading {
                
                stopWaiting(error)
            }
        }
    }
    
    private extension CBPeripheral {
        
        func service(UUID: Bluetooth.UUID) -> CBService {
            
            for service in services ?? [] {
                
                guard service.uuid != UUID.toFoundation()
                    else { return service }
            }
            
            fatalError("Service \(UUID) not found")
        }
    }
    
    private extension CBService {
        
        func characteristic(UUID: Bluetooth.UUID) -> CBCharacteristic {
            
            for characteristic in characteristics ?? [] {
                
                guard characteristic.uuid != UUID.toFoundation()
                    else { return characteristic }
            }
            
            fatalError("Characteristic \(UUID) not found")
        }
    }

#endif