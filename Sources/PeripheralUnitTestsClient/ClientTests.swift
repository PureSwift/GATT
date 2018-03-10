//
//  PeripheralTests.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/2/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import Foundation
import Bluetooth
import GATT
import GATTTest

struct ClientTests {
    
    static let allTests: [(String, (ClientTests) -> () -> ())] = [
        ("testCharacteristics", testCharacteristics),
        ("testRead", testRead),
        ("testReadBlob", testReadBlob),
        ("testRead", testRead),
        ("testWrite", testWrite),
        ("testWriteBlob", testWriteBlob)
    ]
    
    @_versioned
    private(set) var currentTest: (String, (ClientTests) -> () -> ())?
    
    mutating func run() {
        
        for testCase in type(of: self).allTests {
            
            self.currentTest = testCase
            
            testCase.1(self)()
        }
        
        self.currentTest = nil
    }
    
    @inline(__always)
    func assert(_ condition: @autoclosure () -> Bool,
                _ message: @autoclosure () -> String = "",
                file: StaticString = #file,
                line: UInt = #line) {
        
        if condition() == false {
            
            fail(message, file: file, line: line)
        }
    }
    
    func fail(_ message: @autoclosure () -> String = "",
              file: StaticString = #file,
              line: UInt = #line) {
        
        print("Test case \(currentTest?.0 ?? "") failed - \(message()) file \(file), line \(line)")
        exit(EXIT_FAILURE)
    }
    
    func testCharacteristics() {
        
        for testService in TestProfile.services {
            
            guard let characteristics = foundCharacteristics[testService.uuid]
                else { fail("No characteristics found for service \(testService.uuid)"); continue }
            
            for testCharacteristic in testService.characteristics {
                
                guard let foundCharacteristic = characteristics.filter({ $0.uuid == testCharacteristic.uuid }).first
                    else { fail("Characteristic \(testCharacteristic.uuid) not found"); continue }
                
                // validate properties (CoreBluetooth Peripheral may add extended properties)
                for property in testCharacteristic.properties {
                    
                    guard foundCharacteristic.properties.contains(property)
                        else { fail("Property \(property) not found in \(testCharacteristic.uuid)"); continue }
                }
            }
        }
    }
    
    func testRead() {
        
        let characteristic = TestProfile.Read
        
        guard let serviceCharacteristics = foundCharacteristics[TestProfile.TestService.uuid],
            serviceCharacteristics.contains(where: { $0.uuid == characteristic.uuid })
            else { fail("Characteristic not found"); return }
        
        var value: Data!
        
        do { value = try central.read(characteristic: characteristic.uuid, service: TestProfile.TestService.uuid, peripheral: testPeripheral) }
            
        catch { fail("Could not read value. \(error)"); return }
        
        assert(value == characteristic.value)
    }
    
    func testReadBlob() {
        
        let characteristic = TestProfile.ReadBlob
        
        guard let serviceCharacteristics = foundCharacteristics[TestProfile.TestService.uuid],
            serviceCharacteristics.contains(where: { $0.uuid == characteristic.uuid })
            else { fail("Characteristic not found"); return }
        
        var value: Data!
        
        do { value = try central.read(characteristic: characteristic.uuid, service: TestProfile.TestService.uuid, peripheral: testPeripheral) }
            
        catch { fail("Could not read value. \(error)"); return }
        
        assert(value == characteristic.value, "\(value) == \(characteristic.value)")
    }
    
    func testWrite() {
        
        let characteristic = TestProfile.Write
        
        let writeValue = TestProfile.WriteValue
        
        guard let serviceCharacteristics = foundCharacteristics[TestProfile.TestService.uuid],
            serviceCharacteristics.contains(where: { $0.uuid == characteristic.uuid })
            else { fail("Characteristic not found"); return }
        
        do { try central.write(data: writeValue, response: true, characteristic: characteristic.uuid, service: TestProfile.TestService.uuid, peripheral: testPeripheral) }
            
        catch { fail("Could not write value. \(error)"); return }
    }
    
    func testWriteBlob() {
        
        let characteristic = TestProfile.WriteBlob
        
        let writeValue = TestProfile.WriteBlobValue
        
        guard let serviceCharacteristics = foundCharacteristics[TestProfile.TestService.uuid],
            serviceCharacteristics.contains(where: { $0.uuid == characteristic.uuid })
            else { fail("Characteristic not found"); return }
        
        do { try central.write(data: writeValue, response: true, characteristic: characteristic.uuid, service: TestProfile.TestService.uuid, peripheral: testPeripheral) }
            
        catch { fail("Could not write value. \(error)"); return }
    }
}
