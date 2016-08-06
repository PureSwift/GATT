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
    
    static let allTests: [(String, (ServerTests) -> () throws -> Void)] = [("testRead", testRead), ("testWrite", testWrite)]
    
    func testRead() {
        
        let _ = peripheral
        
        for service in TestProfile.services {
            
            for characteristic in service.characteristics {
                
                guard characteristic.permissions.contains(.Read) else { continue }
                
                let didRead = readServices.contains(characteristic.UUID)
                
                XCTAssert(didRead, "Characteristic \(characteristic.UUID) not read")
            }
        }
    }
    
    func testWrite() {
        
        let _ = peripheral
        
        for service in TestProfile.services {
            
            for characteristic in service.characteristics {
                
                guard characteristic.permissions.contains(.Write) else { continue }
                
                let didRead = writtenServices.contains(characteristic.UUID)
                
                XCTAssert(didRead, "Characteristic \(characteristic.UUID) not read")
            }
        }
    }
}
