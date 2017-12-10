//
//  ServerTests.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/3/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import XCTest
import Foundation
import Bluetooth
import GATT
import GATTTest

final class ServerTests: XCTestCase {
    
    static let allTests: [(String, (ServerTests) -> () throws -> ())] = [
        ("testRead", testRead),
        ("testWrite", testWrite)
    ]
    
    func testRead() {
        
        let _ = peripheral
        
        for service in TestProfile.services {
            
            for characteristic in service.characteristics {
                
                guard characteristic.permissions.contains(.read) else { continue }
                
                let didRead = readServices.contains(characteristic.uuid)
                
                XCTAssert(didRead, "Characteristic \(characteristic.uuid) not read")
            }
        }
    }
    
    func testWrite() {
        
        let _ = peripheral
        
        for service in TestProfile.services {
            
            for characteristic in service.characteristics {
                
                guard characteristic.permissions.contains(.write) else { continue }
                
                let didRead = writtenServices.contains(characteristic.uuid)
                
                XCTAssert(didRead, "Characteristic \(characteristic.uuid) not read")
            }
        }
    }
}
