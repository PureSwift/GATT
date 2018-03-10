//
//  CentralManager.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/3/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import Foundation
import Bluetooth
import GATT
import GATTTest

/// The GATT Client / Central Mode
let central = CentralManager()

let testPeripheral: Peripheral = {
    
    central.log = { print("CentralManager: " + $0) }
    
    #if os(macOS) || os(iOS) || os(tvOS) || (os(watchOS) && swift(>=3.2))
    central.waitForPoweredOn()
    #endif
    
    // search until found
    while true {
        
        let foundPeripherals = central.scan(duration: 3)
        
        print("Scan results: \(foundPeripherals.map({ $0.peripheral.identifier }))")
        
        for scanData in foundPeripherals {
            
            let peripheral = scanData.peripheral
            
            do { try central.connect(to: peripheral) }
                
            catch {
                
                print("Error connecting to \(peripheral.identifier): \(error)")
                continue
            }
            
            print("Did connect to \(peripheral.identifier)")
            
            let services = try! central.discoverServices(for: peripheral)
            
            print("Discovered services: \(services.map({ $0.uuid }))")
            
            if services.contains(where: { $0.uuid == TestProfile.TestService.uuid }) {
                
                testServicesCache = services
                
                return peripheral
            }
        }
    }
}()


private var testServicesCache: [CentralManager.Service]!


let foundServices: [CentralManager.Service] = {
   
    // get the peripheral first
    let _ = testPeripheral
    
    // return the cached services
    return testServicesCache
}()


let foundCharacteristics: [BluetoothUUID: [CentralManager.Characteristic]] = {
    
    var found: [BluetoothUUID: [CentralManager.Characteristic]] = [:]
    
    for service in foundServices {
        
        let characteristics = try! central.discoverCharacteristics(for: service.uuid, peripheral: testPeripheral)
        
        print("Found \(characteristics.count) characteristics for service \(service.uuid)")
        
        found[service.uuid] = characteristics
    }
    
    return found
}()


let foundCharacteristicValues: [BluetoothUUID: Data] = {
    
    var values: [BluetoothUUID: Data] = [:]
    
    for (service, characteristics) in foundCharacteristics {
        
        /// Read the value of characteristics that are Readable
        for characteristic in characteristics where characteristic.properties.contains(.read) {
            
            let data = try! central.read(characteristic: characteristic.uuid, service: service, peripheral: testPeripheral)
            
            print("Read characteristic \(characteristic.uuid) (\(data.count) bytes)")
            
            values[characteristic.uuid] = data
        }
    }
    
    return values
}()
