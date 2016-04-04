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

private var testServicesCache: [(UUID: Bluetooth.UUID, primary: Bool)]!

let testPeripheral: Peripheral = {
    
    //central.log = { print("CentralManager: " + $0) }
    
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
                
                testServicesCache = services
                
                return peripheral
            }
        }
    }
}()

let foundServices: [(UUID: Bluetooth.UUID, primary: Bool)] = {
   
    // get the peripheral first
    testPeripheral
    
    // return the cached services
    return testServicesCache
}()
