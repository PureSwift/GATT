//
//  Peripheral.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 7/17/18.
//

#if canImport(Foundation)
import Foundation
#endif
#if canImport(BluetoothGATT)
import Bluetooth
import BluetoothGATT

internal final class GATTServerConnection <Socket: L2CAPConnection>: @unchecked Sendable {
    
    typealias Data = Socket.Data
    
    typealias Error = Socket.Error
    
    // MARK: - Properties
    
    public let central: Central
        
    private let server: GATTServer<Socket>
    
    public var maximumUpdateValueLength: Int {
        // ATT_MTU-3
        Int(server.maximumTransmissionUnit.rawValue) - 3
    }
    
    private let lock = NSLock()
    
    // MARK: - Initialization
    
    internal init(
        central: Central,
        socket: Socket,
        maximumTransmissionUnit: ATTMaximumTransmissionUnit,
        maximumPreparedWrites: Int,
        database: GATTDatabase<Socket.Data>,
        callback: GATTServer<Socket>.Callback,
        log: (@Sendable (String) -> ())?
    ) {
        self.central = central
        self.server = GATTServer(
            socket: socket,
            maximumTransmissionUnit: maximumTransmissionUnit,
            maximumPreparedWrites: maximumPreparedWrites,
            database: database,
            log: log
        )
        self.server.callback = callback
    }
    
    // MARK: - Methods
    
    /// Modify the value of a characteristic, optionally emiting notifications if configured on active connections.
    public func write(_ value: Data, forCharacteristic handle: UInt16) {
        lock.lock()
        defer { lock.unlock() }
        server.writeValue(value, forCharacteristic: handle)
    }
    
    public func run() throws(ATTConnectionError<Socket.Error, Socket.Data>) {
        lock.lock()
        defer { lock.unlock() }
        try self.server.run()
    }
    
    public subscript(handle: UInt16) -> Data {
        lock.lock()
        defer { lock.unlock() }
        return server.database[handle: handle].value
    }
}

#endif
