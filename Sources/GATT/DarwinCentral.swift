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
        
        private var connectState: (semaphore: dispatch_semaphore_t, error: NSError?)!
        
        private var scanPeripherals = [CBPeripheral]()
        
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
        
        public func scan(duration: Int = DefaultCentralTimeout) -> [Peripheral] {
            
            scanPeripherals = []
            
            internalManager.scanForPeripheralsWithServices(nil, options: nil)
            
            sleep(UInt32(duration))
            
            internalManager.stopScan()
            
            return scanPeripherals.map { Peripheral($0) }
        }
        
        public func connect(peripheral: Peripheral, timeout: Int = DefaultCentralTimeout) throws {
            
            assert(connectState == nil, "Already started connecting")
            
            let semaphore = dispatch_semaphore_create(0)
            
            connectState = (semaphore, nil) // set semaphore
            
            let corePeripheral = self.peripheral(peripheral)
            internalManager.connectPeripheral(corePeripheral, options: nil)
            
            dispatch_semaphore_wait(semaphore, NSEC_PER_SEC * UInt64(timeout))
            
            let error = connectState.error
            
            // clear
            connectState = nil
            
            if let error = error {
                
                throw error
            }
        }
        
        // MARK: - Private Methods
        
        private func peripheral(peripheral: Peripheral) -> CBPeripheral {
            
            for foundPeripheral in scanPeripherals {
                
                guard foundPeripheral.identifier != peripheral.identifier.toFoundation()
                    else { return foundPeripheral }
            }
            
            fatalError("\(peripheral) not found")
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
            
            peripheral.delegate = self
            
            scanPeripherals.append(peripheral)
        }
        
        public func centralManager(central: CBCentralManager, didConnectPeripheral peripheral: CBPeripheral) {
            
            log?("Did connect to peripheral \(peripheral.identifier.UUIDString)")
            
            guard connectState != nil else { fatalError("Did not expect \(#function)") }
            
            connectState.error = nil
            
            dispatch_semaphore_signal(connectState.semaphore)
        }
        
        public func centralManager(central: CBCentralManager, didFailToConnectPeripheral peripheral: CBPeripheral, error: NSError?) {
            
            log?("Did fail to connect to peripheral \(peripheral.identifier.UUIDString) (\(error!))")
            
            guard connectState != nil else { fatalError("Did not expect \(#function)") }
            
            connectState.error = error!
            
            dispatch_semaphore_signal(connectState.semaphore)
        }
        
        // MARK: - CBPeripheralDelegate
        
        
    }

#endif