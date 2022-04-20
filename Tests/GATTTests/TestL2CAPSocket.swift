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
internal actor TestL2CAPSocket: L2CAPSocket {
    
    private static var pendingClients = [BluetoothAddress: [TestL2CAPSocket]]()
    
    static func lowEnergyClient(
        address: BluetoothAddress,
        destination: BluetoothAddress,
        isRandom: Bool
    ) async throws -> TestL2CAPSocket {
        let socket = TestL2CAPSocket(
            address: address,
            name: "Client"
        )
        // append to pending clients
        pendingClients[destination, default: []].append(socket)
        // wait until client has connected
        while pendingClients.isEmpty == false {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        return socket
    }
    
    static func lowEnergyServer(
        address: BluetoothAddress,
        isRandom: Bool,
        backlog: Int
    ) async throws -> TestL2CAPSocket {
        return TestL2CAPSocket(
            address: address,
            name: "Server"
        )
    }
    
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
    private weak var target: TestL2CAPSocket?
    
    fileprivate(set) var receivedData = Data()
    
    private(set) var cache = [Data]()
    
    // MARK: - Initialization
    
    private init(
        address: BluetoothAddress = .zero,
        name: String
    ) {
        self.address = address
        self.name = name
    }
    
    // MARK: - Methods
    
    func accept() async throws -> TestL2CAPSocket {
        repeat {
            guard let client = Self.pendingClients[address]?.first else {
                try await Task.sleep(nanoseconds: 10_000_000)
                continue
            }
            Self.pendingClients[address]?.removeFirst()
            // connect sockets
            self.target = client
            await client.setTarget(self)
            return client
        } while true
    }
    
    /// Write to the socket.
    func send(_ data: Data) async throws {
        
        guard let target = self.target
            else { throw POSIXError(.ECONNRESET) }
        
        await target.append(data)
    }
    
    /// Reads from the socket.
    func recieve(_ bufferSize: Int) async throws -> Data {
        
        while self.receivedData.isEmpty {
            try await Task.sleep(nanoseconds: 10_000_000)
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
    
    fileprivate func append(_ data: Data) {
        receivedData.append(data)
        print("L2CAP Socket \(name) \([UInt8](receivedData))")
    }
    
    fileprivate func setTarget(_ socket: TestL2CAPSocket) {
        self.target = socket
    }
}
