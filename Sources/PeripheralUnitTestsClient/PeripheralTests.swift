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

final class PeripheralTests: XCTestCase {
    
    func testGetServices() {
        
        guard let service = CentralManager.manager.fetchTestService()
            else { XCTFail("Could not fetch test service. "); return }
        
        let foundServices = service.peripheral.services ?? []
        
        print("Found services: \(foundServices.map({ $0.UUID.UUIDString }))")
        
        for service in TestData.services {
            
            guard let foundService = foundServices.filter({ Bluetooth.UUID(foundation: $0.UUID) == service.UUID }).first
                else { XCTFail("Test service \(service.UUID) not found"); continue }
            
            /*
            XCTAssert(foundService.isPrimary == service.primary,
                      "Found service \(service.UUID) primary value is \(foundService.isPrimary), should be \(service.primary)")
            */
            
            let foundCharacteristics = foundService.characteristics ?? []
            
            for characteristic in service.characteristics {
                
                guard let foundCharacteristic = foundCharacteristics.filter({ Bluetooth.UUID(foundation: $0.UUID) == characteristic.UUID }).first else { XCTFail("Test characteristic \(characteristic.UUID) not found"); continue }
                
                // validate data
                if characteristic.properties.contains(.Read) {
                    
                    let foundData = Data(foundation: (foundCharacteristic.value ?? NSData()))
                    
                    XCTAssert(foundData == characteristic.value, "Test characteristic \(characteristic.UUID) data does not match. (\(foundData.toFoundation()) == \(characteristic.value.toFoundation()))")
                }
            }
        }
    }
}
