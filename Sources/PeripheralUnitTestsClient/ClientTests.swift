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
    
    func testCharacteristics() {
        
        for testService in TestProfile.services {
            
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
            }
        }
    }
    
    func testRead() {
        
        let characteristic = TestProfile.Read
        
        guard let serviceCharacteristics = foundCharacteristics[TestProfile.TestService.UUID]
            where serviceCharacteristics.contains({ $0.UUID == characteristic.UUID })
            else { XCTFail("Characteristic not found"); return }
        
        var value: Data!
        
        do { value = try central.read(characteristic: characteristic.UUID, service: TestProfile.TestService.UUID, peripheral: testPeripheral) }
            
        catch { XCTFail("Could not read value. \(error)"); return }
        
        XCTAssert(value == characteristic.value)
    }
    
    func testReadBlob() {
        
        let characteristic = TestProfile.ReadBlob
        
        guard let serviceCharacteristics = foundCharacteristics[TestProfile.TestService.UUID]
            where serviceCharacteristics.contains({ $0.UUID == characteristic.UUID })
            else { XCTFail("Characteristic not found"); return }
        
        var value: Data!
        
        do { value = try central.read(characteristic: characteristic.UUID, service: TestProfile.TestService.UUID, peripheral: testPeripheral) }
            
        catch { XCTFail("Could not read value. \(error)"); return }
        
        XCTAssert(value == characteristic.value, "\(value) == \(characteristic.value)")
    }
    
    func testWrite() {
        
        let characteristic = TestProfile.Write
        
        let writeValue = TestProfile.WriteValue
        
        guard let serviceCharacteristics = foundCharacteristics[TestProfile.TestService.UUID]
            where serviceCharacteristics.contains({ $0.UUID == characteristic.UUID })
            else { XCTFail("Characteristic not found"); return }
        
        do { try central.write(data: writeValue, response: true, characteristic: characteristic.UUID, service: TestProfile.TestService.UUID, peripheral: testPeripheral) }
            
        catch { XCTFail("Could not write value. \(error)"); return }
    }
    
    func testWriteBlob() {
        
        let characteristic = TestProfile.WriteBlob
        
        let writeValue = TestProfile.WriteBlobValue
        
        guard let serviceCharacteristics = foundCharacteristics[TestProfile.TestService.UUID]
            where serviceCharacteristics.contains({ $0.UUID == characteristic.UUID })
            else { XCTFail("Characteristic not found"); return }
        
        do { try central.write(data: writeValue, response: true, characteristic: characteristic.UUID, service: TestProfile.TestService.UUID, peripheral: testPeripheral) }
            
        catch { XCTFail("Could not write value. \(error)"); return }
    }
}
