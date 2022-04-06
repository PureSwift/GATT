//
//  Peripheral.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 7/17/18.
//

#if canImport(BluetoothGATT)
import Foundation
import Dispatch
import Bluetooth
import BluetoothGATT

internal final class GATTServerConnection <Socket: L2CAPSocket> {
    
    // MARK: - Properties
    
    let central: Central
    
    unowned let delegate: GATTServerConnectionDelegate
    
    private let server: GATTServer
        
    private func maximumUpdateValueLength() async -> Int {
        // ATT_MTU-3
        return await Int(server.maximumTransmissionUnit.rawValue) - 3
    }
    
    // MARK: - Initialization
    
    public init(
        central: Central,
        socket: Socket,
        maximumTransmissionUnit: ATTMaximumTransmissionUnit,
        maximumPreparedWrites: Int,
        delegate: GATTServerConnectionDelegate
    ) async {
        self.central = central
        self.delegate = delegate
        self.server = await GATTServer(
            socket: socket,
            maximumTransmissionUnit: maximumTransmissionUnit,
            maximumPreparedWrites: maximumPreparedWrites,
            log: { delegate.connection(central, log: $0) }
        )
        // setup callbacks
        await configureServer()
    }
    
    // MARK: - Methods
    
    public func writeValue(_ value: Data, forCharacteristic handle: UInt16) async {
        /*
        await self.server.updateDatabase({ (database) in
            // update server with database from peripheral
            server.database = database
            // modify database
            server.writeValue(value, forCharacteristic: handle)
            // update peripheral database
            database = connection.server.database
        })*/
    }
    
    // IO error
    private func error(_ error: Error) {
        
        self.log("Disconnected \(error)")
        delegate.connection(central, didDisconnect: error)
    }
    
    private func log(_ message: String) {
        delegate.connection(central, log: message)
    }
    
    private func configureServer() async {
        var callback = GATTServer.Callback()
        callback.willRead = { [unowned self] in
            await self.willRead(uuid: $0, handle: $1, value: $2, offset: $3)
        }
        callback.willWrite = { [unowned self] in
            await self.willWrite(uuid: $0, handle: $1, value: $2, newValue: $3)
        }
        callback.didWrite = { [unowned self] in
            await self.didWrite(uuid: $0, handle: $1, value: $2)
        }
        await self.server.setCallbacks(callback)
    }
    
    private func willRead(uuid: BluetoothUUID, handle: UInt16, value: Data, offset: Int) async -> ATTError? {
        let request = GATTReadRequest(
            central: central,
            maximumUpdateValueLength: await maximumUpdateValueLength(),
            uuid: uuid,
            handle: handle,
            value: value,
            offset: offset
        )
        return delegate.connection(central, willRead: request)
    }
    
    private func willWrite(uuid: BluetoothUUID, handle: UInt16, value: Data, newValue: Data) async -> ATTError? {
        let request = GATTWriteRequest(
            central: central,
            maximumUpdateValueLength: await maximumUpdateValueLength(),
            uuid: uuid,
            handle: handle,
            value: value,
            newValue: newValue
        )
        return delegate.connection(central, willWrite: request)
    }
    
    private func didWrite(uuid: BluetoothUUID, handle: UInt16, value: Data) async {
        let confirmation = GATTWriteConfirmation(
            central: central,
            maximumUpdateValueLength: await maximumUpdateValueLength(),
            uuid: uuid,
            handle: handle,
            value: value
        )
        delegate.connection(central, didWrite: confirmation)
    }
}

internal protocol GATTServerConnectionDelegate: AnyObject {
    
    func connection(_ central: Central, log: String)
    
    func connection(_ central: Central, didDisconnect error: Error?)
    
    func connection(_ central: Central, willRead request: GATTReadRequest<Central>) -> ATTError?
    
    func connection(_ central: Central, willWrite request: GATTWriteRequest<Central>) -> ATTError?
        
    func connection(_ central: Central, didWrite confirmation: GATTWriteConfirmation<Central>)
    
    func connection(_ central: Central, access database: inout GATTDatabase)
}

#endif
