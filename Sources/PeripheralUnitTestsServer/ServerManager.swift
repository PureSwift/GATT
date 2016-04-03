//
//  ServerManager.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/3/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import Foundation
import XCTest
import SwiftFoundation
import Bluetooth
import GATT
import GATTTest

final class ServerManager {
    
    static let manager = ServerManager()
    
    // MARK: - Properties
        
    private(set) var readServices: [Bluetooth.UUID] = []
    
    private(set) var writtenServices: [Bluetooth.UUID] = []
    
    private let server: Server
    
    // MARK: - Initialization
    
    private init() {
        
        self.server = Server()
        
        for service in TestData.services {
            
            try! server.add(service)
        }
        
        server.willRead = willRead
        server.willWrite = willWrite
        
        try! server.start()
        
        print("Created server")
        
        let sleepTime: UInt32 = 20
        
        print("Sleeping for \(sleepTime) seconds...")
        
        sleep(sleepTime)
    }
    
    deinit {
        
        server.stop()
    }
    
    // MARK: - Private Methods
    
    private func willRead(central: Central, UUID: Bluetooth.UUID, value: Data, offset: Int) -> ATT.Error? {
        
        print("Central \(central.identifier) will read characteristic \(UUID)")
        
        readServices.append(UUID)
        
        return nil
    }
    
    private func willWrite(central: Central, UUID: Bluetooth.UUID, value: Data, newValue: (newValue: Data, newBytes: Data, offset: Int)) -> ATT.Error? {
        
        print("Central \(central.identifier) will write characteristic \(UUID)")
        
        writtenServices.append(UUID)
        
        return nil
    }
}