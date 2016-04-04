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
            guard internalManager.state != .PoweredOn else { return }
            
            // already waiting
            guard poweredOnSemaphore == nil else { dispatch_semaphore_wait(poweredOnSemaphore, DISPATCH_TIME_FOREVER); return }
            
            log?("Not powered on (State \(internalManager.state.rawValue))")
            
            poweredOnSemaphore = dispatch_semaphore_create(0)
            
            dispatch_semaphore_wait(poweredOnSemaphore, DISPATCH_TIME_FOREVER)
            
            poweredOnSemaphore = nil
            
            assert(internalManager.state == .PoweredOn)
            
            log?("Now powered on")
        }
        
        public func scan(duration: Int = 5) -> [Peripheral] {
            
            scanPeripherals = []
            
            internalManager.scanForPeripheralsWithServices(nil, options: nil)
            
            sleep(UInt32(duration))
            
            internalManager.stopScan()
            
            return scanPeripherals.map { Peripheral($0) }
        }
        
        public func connect(peripheral: Peripheral, timeout: Int = 30) throws {
            
            let corePeripheral = self.peripheral(peripheral)
            
            connectingToPeripheral = corePeripheral
            
            internalManager.connectPeripheral(corePeripheral, options: nil)
            
            try wait(NSEC_PER_SEC * UInt64(timeout))
            
            connectingToPeripheral = nil
            
            guard corePeripheral.state == .Connected
                else { throw Error.Timeout }
        }
        
        public func discover(services peripheral: Peripheral) throws -> [(UUID: Bluetooth.UUID, primary: Bool)] {
            
            let corePeripheral = self.peripheral(peripheral)
            
            corePeripheral.discoverServices(nil)
            
            try wait()
            
            return (corePeripheral.services ?? []).map { (Bluetooth.UUID(foundation: $0.UUID), $0.isPrimary) }
        }
        
        public func discover(characteristics service: Bluetooth.UUID, peripheral: Peripheral) throws -> [(UUID: Bluetooth.UUID, properties: [Characteristic.Property])] {
            
            let corePeripheral = self.peripheral(peripheral)
            
            let coreService = corePeripheral.service(service)
            
            corePeripheral.discoverCharacteristics(nil, forService: coreService)
            
            try wait()
            
            return (coreService.characteristics ?? []).map { (Bluetooth.UUID(foundation: $0.UUID), Characteristic.Property.from($0.properties)) }
        }
        
        public func read(characteristic UUID: Bluetooth.UUID, service: Bluetooth.UUID, peripheral: Peripheral) throws -> Data {
            
            let corePeripheral = self.peripheral(peripheral)
            
            let coreService = corePeripheral.service(service)
            
            let coreCharacteristic = coreService.characteristic(UUID)
            
            corePeripheral.readValueForCharacteristic(coreCharacteristic)
            
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
        
        private func wait(time: UInt64 = DISPATCH_TIME_FOREVER) throws {
            
            assert(operationState == nil, "Already waiting for an asyncronous operation to finish")
            
            let semaphore = dispatch_semaphore_create(0)
            
            // set semaphore
            operationState = (semaphore, nil)
            
            // wait
            dispatch_semaphore_wait(semaphore, time)
            
            let error = operationState.error
            
            // clear state
            operationState = nil
            
            if let error = error {
                
                throw error
            }
        }
        
        private func stopWaiting(error: NSError? = nil, _ function: String = #function) {
            
            assert(operationState != nil, "Did not expect \(function)")
            
            operationState.error = error
            
            dispatch_semaphore_signal(operationState.semaphore)
        }
        
        /// Perform a task on the internal queue and wait. Can throw error.
        private func sync<T>(block: () throws -> T) throws -> T {
            
            var blockValue: T!
            
            var caughtError: ErrorType?
            
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
            
            log?("Did update state (\(central.state == .PoweredOn ? "Powered On" : "\(central.state.rawValue)"))")
            
            if central.state == .PoweredOn && poweredOnSemaphore != nil {
                
                dispatch_semaphore_signal(poweredOnSemaphore)
            }
        }
        
        public func centralManager(central: CBCentralManager, didDiscoverPeripheral peripheral: CBPeripheral, advertisementData: [String : AnyObject], RSSI: NSNumber) {
            
            log?("Did discover peripheral \(peripheral)")
            
            if peripheral.delegate == nil {
                
                peripheral.delegate = self
            }
            
            if scanPeripherals.contains(peripheral) == false {
                
                scanPeripherals.append(peripheral)
            }
        }
        
        public func centralManager(central: CBCentralManager, didConnectPeripheral peripheral: CBPeripheral) {
            
            log?("Did connect to peripheral \(peripheral.identifier.UUIDString)")
            
            if connectingToPeripheral?.identifier == peripheral.identifier {
                
                stopWaiting()
            }
        }
        
        public func centralManager(central: CBCentralManager, didFailToConnectPeripheral peripheral: CBPeripheral, error: NSError?) {
            
            log?("Did fail to connect to peripheral \(peripheral.identifier.UUIDString) (\(error!))")
            
            stopWaiting(error)
        }
        
        // MARK: - CBPeripheralDelegate
        
        public func peripheral(peripheral: CBPeripheral, didDiscoverServices error: NSError?) {
            
            if let error = error {
                
                log?("Error discovering services (\(error))")
                return
                
            } else {
                
                log?("Peripheral \(peripheral.identifier.UUIDString) did discover \(peripheral.services?.count ?? 0) services")
            }
            
            stopWaiting()
        }
        
        public func peripheral(peripheral: CBPeripheral, didDiscoverCharacteristicsForService service: CBService, error: NSError?) {
            
            if let error = error {
                
                log?("Error discovering characteristics (\(error))")
                return
                
            } else {
                
                log?("Peripheral \(peripheral.identifier.UUIDString) did discover \(service.characteristics?.count ?? 0) characteristics for service \(service.UUID.UUIDString)")
            }
            
            stopWaiting()
        }
        
        public func peripheral(peripheral: CBPeripheral, didUpdateValueForCharacteristic characteristic: CBCharacteristic, error: NSError?) {
            
            if let error = error {
                
                log?("Error reading characteristic (\(error))")
                return
                
            } else {
                
                log?("Peripheral \(peripheral.identifier.UUIDString) did update value for characteristic \(characteristic.UUID.UUIDString)")
            }
            
            if isReading {
                
                stopWaiting()
            }
        }
    }
    
    private extension CBPeripheral {
        
        func service(UUID: Bluetooth.UUID) -> CBService {
            
            for service in services ?? [] {
                
                guard service.UUID != UUID.toFoundation()
                    else { return service }
            }
            
            fatalError("Service \(UUID) not found")
        }
    }
    
    private extension CBService {
        
        func characteristic(UUID: Bluetooth.UUID) -> CBCharacteristic {
            
            for characteristic in characteristics ?? [] {
                
                guard characteristic.UUID != UUID.toFoundation()
                    else { return characteristic }
            }
            
            fatalError("Characteristic \(UUID) not found")
        }
    }

#endif