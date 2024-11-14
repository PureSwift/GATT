//
//  Peripheral.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 7/17/18.
//

#if canImport(BluetoothGATT)
import Bluetooth
import BluetoothGATT

internal actor GATTServerConnection <Socket: L2CAPConnection> {
    
    typealias Data = Socket.Data
    
    // MARK: - Properties
    
    let central: Central
        
    let server: GATTServer<Socket>
    
    var maximumUpdateValueLength: Int {
        // ATT_MTU-3
        Int(server.maximumTransmissionUnit.rawValue) - 3
    }
    
    // MARK: - Initialization
    
    init(
        central: Central,
        socket: Socket,
        maximumTransmissionUnit: ATTMaximumTransmissionUnit,
        maximumPreparedWrites: Int,
        database: GATTDatabase<Socket.Data>,
        delegate: GATTServer<Socket>.Callback,
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
    }
    
    // MARK: - Methods
    
    /// Modify the value of a characteristic, optionally emiting notifications if configured on active connections.
    func write(_ value: Data, forCharacteristic handle: UInt16) {
        server.writeValue(value, forCharacteristic: handle)
    }
    
    func run() throws(ATTConnectionError<Socket.Error, Socket.Data>) {
        try self.server.run()
    }
    
    subscript(handle: UInt16) -> Data {
        server.database[handle: handle].value
    }
}

#endif
