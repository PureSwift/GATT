//
//  CentralManager.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/3/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import Foundation
import CoreBluetooth
import XCTest
import SwiftFoundation
import Bluetooth
import GATT
import GATTTest

let central = CentralManager()

let testPeripheral: Peripheral = {
    
    central.log = { print("CentralManager: " + $0) }
    
    central.waitForPoweredOn()
    
    // search until found
    while true {
        
        let foundPeripherals = central.scan()
        
        print("Scan results: \(foundPeripherals.map({ $0.identifier }))")
        
        for peripheral in foundPeripherals {
            
            do { try central.connect(peripheral) }
                
            catch {
                
                print("Error connecting to \(peripheral.identifier): \(error)")
                continue
            }
            
            print("Did connect to \(peripheral.identifier)")
            
            let services = try! central.discover(services: peripheral)
            
            print("Discovered services: \(services.map({ $0.UUID }))")
            
            if services.contains({ $0.UUID == TestData.testService.UUID }) {
                
                return peripheral
            }
        }
    }
}()

final class TestCentralManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    // MARK: - Properties
    
    static let manager = TestCentralManager()
    
    let scanDuration: UInt32 = 10
    
    private lazy var internalManager: CBCentralManager = CBCentralManager(delegate: self, queue: self.queue)
    
    private lazy var queue = dispatch_queue_create("CentralManager Queue", nil)
    
    private var testService: CBService?
    
    private var didScan = false
    
    private var poweredOnSemaphore: dispatch_semaphore_t!
    
    private var foundPeripheral: CBPeripheral?
    
    deinit {
        
        if let foundPeripheral = foundPeripheral {
            
            internalManager.cancelPeripheralConnection(foundPeripheral)
        }
    }
    
    // MARK: - Methods
    
    func fetchTestService() -> CBService? {
        
        // return cached service
        if let testService = testService {
            
            return testService
        }
        
        guard didScan == false else { return nil }
        
        /// wait for on state
        waitForPoweredOn()
        
        log("Searching for test service \(TestData.testService.UUID)")
        
        if let connectedPeripheral = internalManager.retrieveConnectedPeripheralsWithServices([TestData.testService.UUID.toFoundation()]).first {
            
            foundPeripheral = connectedPeripheral
            
            connectedPeripheral.delegate = self
            
            switch connectedPeripheral.state {
                
            case .Disconnected:
                
                fatalError("Peripheral \(connectedPeripheral) should be connected")
                
            case .Connecting:
                
                break
                
            case .Connected:
                
                connectedPeripheral.discoverServices(nil)
            }
            
        } else {
            
            log("No connected peripheral with the test service was found, will scan")
            
            internalManager.scanForPeripheralsWithServices(nil, options: nil)
        }
        
        print("Waiting for \(scanDuration) seconds")
        
        sleep(scanDuration)
        
        didScan = true
        
        return testService
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
    
    /*
     func centralManager(central: CBCentralManager, didRetrieveConnectedPeripherals peripherals: [CBPeripheral]) {
     
     log("Did retrieve connected peripherals: \(peripherals)")
     
     guard let testPeripheral = peripherals.filter({ ($0.services ?? []).contains({ $0.UUID == TestData.testService.UUID.toFoundation() }) }).first else {
     
     log("No connected peripheral with the test service was found, will scan")
     
     internalManager.scanForPeripheralsWithServices(nil, options: nil)
     
     return
     }
     
     foundPeripheral = testPeripheral
     
     testPeripheral.delegate = self
     
     switch testPeripheral.state {
     
     case .Disconnected:
     
     fatalError("Peripheral \(testPeripheral) should be connected in \(#function)")
     
     case .Connecting:
     
     break
     
     case .Connected:
     
     testPeripheral.discoverServices(nil)
     }
     }*/
    
    func centralManager(central: CBCentralManager, didDiscoverPeripheral peripheral: CBPeripheral, advertisementData: [String : AnyObject], RSSI: NSNumber) {
        
        log("Did discover peripheral \(peripheral)")
        
        central.stopScan()
        
        peripheral.delegate = self
        
        foundPeripheral = peripheral
        
        switch peripheral.state {
            
        case .Disconnected:
            
            internalManager.connectPeripheral(peripheral, options: nil)
            
        case .Connecting: break
            
        case .Connected:
            
            peripheral.discoverServices(nil)
        }
    }
    
    func centralManager(central: CBCentralManager, didConnectPeripheral peripheral: CBPeripheral) {
        
        log("Did connect to peripheral \(peripheral.identifier.UUIDString)")
        
        peripheral.discoverServices(nil)
    }
    
    func centralManager(central: CBCentralManager, didFailToConnectPeripheral peripheral: CBPeripheral, error: NSError?) {
        
        fatalError("Could not connect to peripheral \(peripheral) (\(error))")
    }
    
    // MARK: - CBPeripheralDelegate
    
    func peripheral(peripheral: CBPeripheral, didDiscoverServices error: NSError?) {
        
        log("Peripheral \(peripheral.identifier.UUIDString) did discover services")
        
        if let error = error {
            
            log("Error discovering services (\(error))")
            
            return
        }
        
        let serviceUUIDs = peripheral.services?.map({ Bluetooth.UUID(foundation: $0.UUID) }) ?? []
        
        guard serviceUUIDs.contains(TestData.testService.UUID) else {
            
            print("Peripheral \(peripheral.identifier.UUIDString) does not contain the test service UUID, will continue scanning")
            
            foundPeripheral = nil
            
            internalManager.cancelPeripheralConnection(peripheral)
            
            internalManager.scanForPeripheralsWithServices(nil, options: nil)
            
            return
        }
        
        self.testService = peripheral.services!.filter({ $0.UUID == TestData.testService.UUID.toFoundation() }).first!
        
        for service in peripheral.services ?? [] {
            
            log("Discovering characteristics for service \(service.UUID.UUIDString)")
            
            peripheral.discoverCharacteristics(nil, forService: service)
        }
    }
    
    func peripheral(peripheral: CBPeripheral, didDiscoverCharacteristicsForService service: CBService, error: NSError?) {
        
        log("Peripheral \(peripheral.identifier.UUIDString) did discover \(service.characteristics?.count ?? 0) characteristics for service \(service.UUID.UUIDString)")
        
        if let error = error {
            
            log("Error discovering characteristics (\(error))")
            
            return
        }
        
        for characteristic in service.characteristics ?? [] {
            
            peripheral.readValueForCharacteristic(characteristic)
        }
    }
    
    func peripheral(peripheral: CBPeripheral, didUpdateValueForCharacteristic characteristic: CBCharacteristic, error: NSError?) {
        
        log("Peripheral \(peripheral.identifier.UUIDString) did update value for characteristic \(characteristic.UUID.UUIDString)")
        
        
    }
}
