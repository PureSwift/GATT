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
import Foundation
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
            
            do { try central.connect(to: peripheral) }
                
            catch {
                
                print("Error connecting to \(peripheral.identifier): \(error)")
                continue
            }
            
            print("Did connect to \(peripheral.identifier)")
            
            let services = try! central.discoverServices(for: peripheral)
            
            print("Discovered services: \(services.map({ $0.UUID }))")
            
            if services.contains(where: { $0.UUID == TestProfile.TestService.UUID }) {
                
                testServicesCache = services
                
                return peripheral
            }
        }
    }
}()

private var testServicesCache: [(UUID: BluetoothUUID, primary: Bool)]!

let foundServices: [(UUID: BluetoothUUID, primary: Bool)] = {
   
    // get the peripheral first
    let _ = testPeripheral
    
    // return the cached services
    return testServicesCache
}()

let foundCharacteristics: [BluetoothUUID: [(UUID: BluetoothUUID, properties: [Characteristic.Property])]] = {
    
    var found: [BluetoothUUID: [(UUID: BluetoothUUID, properties: [Characteristic.Property])]] = [:]
    
    for service in foundServices {
        
        let characteristics = try! central.discoverCharacteristics(for: service.UUID, peripheral: testPeripheral)
        
        print("Found \(characteristics.count) characteristics for service \(service.UUID)")
        
        found[service.UUID] = characteristics
    }
    
    return found
}()

let foundCharacteristicValues: [BluetoothUUID: Data] = {
    
    var values: [BluetoothUUID: Data] = [:]
    
    for (service, characteristics) in foundCharacteristics {
        
        /// Read the value of characteristics that are Readable
        for characteristic in characteristics where characteristic.properties.contains(.Read) {
            
            let data = try! central.read(characteristic: characteristic.UUID, service: service, peripheral: testPeripheral)
            
            print("Read characteristic \(characteristic.UUID) (\(data.bytes.count) bytes)")
            
            values[characteristic.UUID] = data
        }
    }
    
    return values
}()
