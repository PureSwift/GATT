//
//  ServerTests.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/3/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import Foundation
import Bluetooth
import GATT
import GATTTest

struct ServerTests {
    
    static let allTests: [(String, (ServerTests) -> () -> ())] = [
        ("testRead", testRead),
        ("testWrite", testWrite)
    ]
    
    @_versioned
    private(set) var currentTest: (String, (ServerTests) -> () -> ())?
    
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
            
            print("Test case \(currentTest?.0 ?? "") failed - \(message()) file \(file), line \(line)")
            exit(EXIT_FAILURE)
        }
    }
    
    func testRead() {
        
        let _ = peripheral
        
        for service in TestProfile.services {
            
            for characteristic in service.characteristics {
                
                guard characteristic.permissions.contains(.read) else { continue }
                
                let didRead = readServices.contains(characteristic.uuid)
                
                assert(didRead, "Characteristic \(characteristic.uuid) not read")
            }
        }
    }
    
    func testWrite() {
        
        let _ = peripheral
        
        for service in TestProfile.services {
            
            for characteristic in service.characteristics {
                
                guard characteristic.permissions.contains(.write) else { continue }
                
                let didRead = writtenServices.contains(characteristic.uuid)
                
                assert(didRead, "Characteristic \(characteristic.uuid) not read")
            }
        }
    }
}
