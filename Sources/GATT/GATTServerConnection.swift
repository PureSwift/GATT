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
    
    /*
    private func configureServer() async {
        var callback = GATTServer<Socket>.Callback()
        callback.willRead = { [weak self] in
            await self?.willRead(uuid: $0, handle: $1, value: $2, offset: $3)
        }
        callback.willWrite = { [weak self] in
            await self?.willWrite(uuid: $0, handle: $1, value: $2, newValue: $3)
        }
        callback.didWrite = { [weak self] in
            await self?.didWrite(uuid: $0, handle: $1, value: $2)
        }
        await self.server.callback = callback
    }
    
    private func willRead(uuid: BluetoothUUID, handle: UInt16, value: Socket.Data, offset: Int) async -> ATTError? {
        let request = GATTReadRequest(
            central: central,
            maximumUpdateValueLength: await maximumUpdateValueLength,
            uuid: uuid,
            handle: handle,
            value: value,
            offset: offset
        )
        return await delegate?.connection(central, willRead: request)
    }
    
    private func willWrite(uuid: BluetoothUUID, handle: UInt16, value: Socket.Data, newValue: Data) async -> ATTError? {
        let request = GATTWriteRequest(
            central: central,
            maximumUpdateValueLength: await maximumUpdateValueLength,
            uuid: uuid,
            handle: handle,
            value: value,
            newValue: newValue
        )
        return await delegate?.connection(central, willWrite: request)
    }
    
    private func didWrite(uuid: BluetoothUUID, handle: UInt16, value: Socket.Data) async {
        let confirmation = GATTWriteConfirmation(
            central: central,
            maximumUpdateValueLength: await maximumUpdateValueLength,
            uuid: uuid,
            handle: handle,
            value: value
        )
        await delegate?.connection(central, didWrite: confirmation)
    }*/
}

#endif
