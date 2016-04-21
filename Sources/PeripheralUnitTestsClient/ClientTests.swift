//
//  PeripheralTests.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/2/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import XCTest
import Foundation
import CoreBluetooth
import SwiftFoundation
import Bluetooth
import GATT
import GATTTest

final class ClientTests: XCTestCase {
    
    func testServices() {
        
        for testService in TestData.services {
            
            guard let foundService = foundServices.filter({ $0.UUID == TestData.testService.UUID }).first
                else { XCTFail("Service \(testService.UUID) not found"); continue }
            
            /*
            XCTAssert(foundService.primary == testService.primary,
                      "Service \(testService.UUID) primary is \(foundService.primary), should be \(testService.primary)")
            */
        }
    }
    
    func testCharacteristics() {
        
        for testService in TestData.services {
            
            guard let characteristics = foundCharacteristics[testService.UUID]
                else { XCTFail("No characteristics found for service \(testService.UUID)"); continue }
            
            for testCharacteristic in testService.characteristics {
                
                guard let foundCharacteristic = characteristics.filter({ $0.UUID == testCharacteristic.UUID }).first
                    else { XCTFail("Characteristic \(testCharacteristic.UUID) not found"); continue }
                
                // validate properties (CoreBluetooth Peripheral may add extended properties)
                for property in testCharacteristic.properties {
                    
                    guard foundCharacteristic.properties.contains(property)
                        else { XCTFail("Property \(property) not found in \(testCharacteristic.UUID)"); continue }
                }
                
                // permissions are server-side only
                
                // read value
                if testCharacteristic.properties.contains(.Read) {
                    
                    let foundData = foundCharacteristicValues[testCharacteristic.UUID]
                    
                    XCTAssert(foundData == testCharacteristic.value, "Invalid value for characteristic \(testCharacteristic.UUID)")
                }
            }
        }
    }
    
    func testWrite() {
        
        // make sure values are already read
        foundCharacteristicValues
        
        do { try central.write(data: TestData.writeOnly.newValue, response: true, characteristic: TestData.writeOnly.characteristic.UUID, service: TestData.writeOnly.service, peripheral: testPeripheral) }
        
        catch { XCTFail("Could not write value. \(error)"); return }
    }
    
    func testLongWrite() {
        
        // make sure values are already read
        foundCharacteristicValues
        
        let newValue = Data(byteValue: [Byte].init(repeating: UInt8.max, count: 512))
        
        do { try central.write(data: newValue, response: true, characteristic: TestData.services[1].characteristics[1].UUID, service: TestData.services[1].UUID, peripheral: testPeripheral) }
            
        catch { XCTFail("Could not write long value. \(error)"); return }
    }
}
