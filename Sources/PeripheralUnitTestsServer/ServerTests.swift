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
    
    static let allTests: [(String, ServerTests -> () throws -> Void)] = [("testRead", testRead)]
    
    func testRead() {
        
        peripheral
        
        for service in TestProfile.services {
            
            for characteristic in service.characteristics {
                
                guard characteristic.permissions.contains(.Read) else { continue }
                
                let didRead = readServices.contains(characteristic.UUID)
                
                XCTAssert(didRead, "Characteristic \(characteristic.UUID) not read")
            }
        }
    }
}
