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
        print("Client \(address) will connect to \(destination)")
        // append to pending clients
        pendingClients[destination, default: []].append(socket)
        // wait until client has connected
        while (pendingClients[destination] ?? []).isEmpty == false {
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
        while (Self.pendingClients[address] ?? []).isEmpty {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let client = Self.pendingClients[address]!.removeFirst()
        let newConnection = TestL2CAPSocket(address: client.address, name: "Server connection")
        // connect sockets
        await newConnection.connect(to: client)
        await client.connect(to: newConnection)
        return newConnection
    }
    
    /// Write to the socket.
    func send(_ data: Data) async throws {
        
        print("L2CAP Socket: \(name) will send \(data.count) bytes")
        
        guard let target = self.target
            else { throw POSIXError(.ECONNRESET) }
        
        await target.receive(data)
    }
    
    /// Reads from the socket.
    func recieve(_ bufferSize: Int) async throws -> Data {
        
        print("L2CAP Socket: \(name) will read \(bufferSize) bytes")
        
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
    
    fileprivate func receive(_ data: Data) {
        receivedData.append(data)
        print("L2CAP Socket: \(name) recieved \([UInt8](receivedData))")
    }
    
    fileprivate func connect(to socket: TestL2CAPSocket) {
        self.target = socket
    }
}
