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
        
    private actor Cache {
        
        static let shared = Cache()
        
        private init() { }
        
        var pendingClients = [BluetoothAddress: [TestL2CAPSocket]]()
        
        func queue(client socket: TestL2CAPSocket, server: BluetoothAddress) {
            pendingClients[server, default: []].append(socket)
        }
        
        func dequeue(server: BluetoothAddress) -> TestL2CAPSocket? {
            guard let socket = pendingClients[server]?.first else {
                return nil
            }
            pendingClients[server]?.removeFirst()
            return socket
        }
    }
    
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
        await Cache.shared.queue(client: socket, server: destination)
        // wait until client has connected
        while await (Cache.shared.pendingClients[destination] ?? []).contains(where: { $0 === socket }) {
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
    
    private(set) var event: ((L2CAPSocketEvent) async -> ()) = { _ in }
    
    func setEvent(_ event: @escaping ((L2CAPSocketEvent) async -> ())) async {
        self.event = event
    }
    
    /// The socket's security level.
    private(set) var securityLevel: SecurityLevel = .sdp
    
    /// Attempts to change the socket's security level.
    func setSecurityLevel(_ securityLevel: SecurityLevel) throws {
        self.securityLevel = securityLevel
    }
    
    /// Target socket.
    private weak var target: TestL2CAPSocket?
    
    fileprivate(set) var receivedData = [Data]()
    
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
        // sleep until a client socket is created
        while (await Cache.shared.pendingClients[address] ?? []).isEmpty {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let client = await Cache.shared.dequeue(server: address)!
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
        Task.detached(priority: .high) { [weak self] in
            await self?.event(.write(data.count))
        }
    }
    
    /// Reads from the socket.
    func recieve(_ bufferSize: Int) async throws -> Data {
        
        print("L2CAP Socket: \(name) will read \(bufferSize) bytes")
        
        while self.receivedData.isEmpty {
            guard self.target != nil
                else { throw POSIXError(.ECONNRESET) }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        
        let data = self.receivedData.removeFirst()
        cache.append(data)
        Task.detached(priority: .high) { [weak self] in
            await self?.event(.read(data.count))
        }
        return data
    }
    
    fileprivate func receive(_ data: Data) {
        receivedData.append(data)
        print("L2CAP Socket: \(name) recieved \([UInt8](data))")
        Task.detached(priority: .high) { [weak self] in
            await self?.event(.pendingRead)
        }
    }
    
    fileprivate func connect(to socket: TestL2CAPSocket) {
        self.target = socket
    }
}
