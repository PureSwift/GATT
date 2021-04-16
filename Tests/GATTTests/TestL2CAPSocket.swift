//
//  L2CAPSocket.swift
//  BluetoothTests
//
//  Created by Alsey Coleman Miller on 3/30/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import Bluetooth
import GATT

/// Test L2CAP socket
internal final class TestL2CAPSocket: L2CAPSocketProtocol {
    
    // MARK: - Properties
    
    let name: String
    
    let address: BluetoothAddress
    
    /// The socket's security level.
    private(set) var securityLevel: SecurityLevel = .sdp
    
    /// Attempts to change the socket's security level.
    func setSecurityLevel(_ securityLevel: SecurityLevel) throws {
        
        self.securityLevel = securityLevel
    }
    
    /// Target socket.
    weak var target: TestL2CAPSocket?
    
    fileprivate(set) var receivedData = Data() {
        
        didSet { if receivedData.isEmpty == false { print("L2CAP Socket \(name) \([UInt8](receivedData))") } }
    }
    
    private(set) var cache = [Data]()
    
    init(address: BluetoothAddress = .zero,
         name: String = "") {
        
        self.address = address
        self.name = name
    }
    
    // MARK: - Methods
    
    /// Write to the socket.
    func send(_ data: Data) throws {
        
        guard let target = self.target
            else { throw POSIXError(.ECONNRESET) }
        
        target.receivedData.append(data)
    }
    
    /// Reads from the socket.
    func recieve(_ bufferSize: Int) throws -> Data? {
        
        if self.receivedData.isEmpty {
            
            return nil
        }
        
        let data = Data(receivedData.prefix(bufferSize))
        
        // slice buffer
        if data.isEmpty == false {
            
            let suffixIndex = data.count
            
            if receivedData.count >= suffixIndex {
                
                receivedData = Data(receivedData.suffix(from: data.count))
                
            } else {
                
                receivedData = Data(receivedData.suffix(from: data.count))
            }
        }
        
        cache.append(data)
        
        return data
    }
}
