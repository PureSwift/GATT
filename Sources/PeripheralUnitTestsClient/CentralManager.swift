//
//  CentralManager.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/3/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import Foundation
import CoreBluetooth
import Bluetooth
import GATT
import GATTTest

final class CentralManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    // MARK: - Properties
    
    static let manager = CentralManager()
    
    lazy var internalManager: CBCentralManager = CBCentralManager(delegate: self, queue: self.queue)
    
    lazy var queue = dispatch_queue_create("CentralManager Queue", nil)
    
    private var testService: CBService?
    
    private var testServiceSemaphore: dispatch_semaphore_t!
    
    private var poweredOnSemaphore: dispatch_semaphore_t!
    
    // MARK: - Methods
    
    func fetchTestService() -> CBService {
        
        // return cached service
        if let testService = testService {
            
            return testService
        }
        
        /// wait for on state
        waitForPoweredOn()
        
        log("Searching for test service \(TestData.testService.UUID)")
        
        internalManager.scanForPeripheralsWithServices([TestData.testService.UUID.toFoundation()], options: nil)
        
        testServiceSemaphore = dispatch_semaphore_create(0)
        
        dispatch_semaphore_wait(testServiceSemaphore, DISPATCH_TIME_FOREVER)
        
        return testService!
    }
    
    private func waitForPoweredOn() {
        
        // already on
        guard internalManager.state != .PoweredOn else { return }
        
        // already waiting
        guard poweredOnSemaphore == nil else { dispatch_semaphore_wait(poweredOnSemaphore, DISPATCH_TIME_FOREVER); return }
        
        log("Not powered on (State \(internalManager.state.rawValue))")
        
        poweredOnSemaphore = dispatch_semaphore_create(0)
        
        dispatch_semaphore_wait(poweredOnSemaphore, DISPATCH_TIME_FOREVER)
        
        poweredOnSemaphore = nil
        
        assert(internalManager.state == .PoweredOn)
        
        log("Now powered on")
    }
    
    @inline(__always)
    private func log(message: String) {
        
        print("CentralManager: " + message)
    }
    
    // MARK: - CBCentralManagerDelegate
    
    @objc internal func centralManagerDidUpdateState(central: CBCentralManager) {
        
        log("Did update state (\(central.state == .PoweredOn ? "Powered On" : "\(central.state.rawValue)"))")
        
        if central.state == .PoweredOn && poweredOnSemaphore != nil {
            
            dispatch_semaphore_signal(poweredOnSemaphore)
        }
    }
    
    func centralManager(central: CBCentralManager, didRetrievePeripherals peripherals: [CBPeripheral]) {
        
        log("Did retrieve peripherals \(peripherals.map({ $0.identifier.UUIDString })), discovering services")
        
        for peripheral in peripherals {
            
            peripheral.delegate = self
            
            peripheral.discoverServices(nil)
        }
    }
    
    func centralManager(central: CBCentralManager, didConnectPeripheral peripheral: CBPeripheral) {
        
        log("Did connect to peripheral \(peripheral.identifier.UUIDString)")
        
        
    }
    
    // MARK: - CBPeripheralDelegate
    
    func peripheral(peripheral: CBPeripheral, didDiscoverServices error: NSError?) {
        
        log("Peripheral \(peripheral) did discover services")
        
        if let error = error {
            
            log("Error discovering services (\(error))")
            
            return
        }
        
        for service in peripheral.services ?? [] {
            
            log("Discovering characteristics for service \(service.UUID.UUIDString)")
            
            peripheral.discoverCharacteristics(nil, forService: service)
        }
    }
}