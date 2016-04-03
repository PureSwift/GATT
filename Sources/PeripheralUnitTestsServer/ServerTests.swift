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

    func testServer() {
        
        let server = Server()
        
        for service in TestData.services {
            
            try! server.add(service)
        }
        
        let sleepTime: UInt32 = 10
        
        print("Sleeping for \(sleepTime) seconds...")
        
        sleep(sleepTime)
    }
}
