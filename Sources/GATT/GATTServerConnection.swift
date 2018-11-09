//
//  Peripheral.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 7/17/18.
//

import Foundation
import Dispatch
import Bluetooth

#if os(macOS) || os(Linux)

@available(macOS 10.12, *)
public final class GATTServerConnection <L2CAPSocket: L2CAPSocketProtocol> {
    
    // MARK: - Properties
    
    public let central: Central
    
    public var callback = GATTServerConnectionCallback()
    
    internal let server: GATTServer
    
    internal private(set) var isRunning: Bool = true
    
    private lazy var readThread: Thread = Thread { [weak self] in
        
        // run until object is released
        while let connection = self {
            
            // run the main loop exactly once.
            self?.readMain()
        }
    }
    
    internal lazy var writeQueue: DispatchQueue = DispatchQueue(label: "\(type(of: self)) \(self.central) Write Queue")
    
    internal var maximumUpdateValueLength: Int {
        
        // ATT_MTU-3
        return Int(server.maximumTransmissionUnit.rawValue) - 3
    }
    
    // MARK: - Initialization
    
    public init(central: Central,
                socket: L2CAPSocket,
                maximumTransmissionUnit: ATTMaximumTransmissionUnit,
                maximumPreparedWrites: Int) {
        
        self.central = central
        self.server = GATTServer(socket: socket,
                                 maximumTransmissionUnit: maximumTransmissionUnit,
                                 maximumPreparedWrites: maximumPreparedWrites)
        
        // setup callbacks
        self.configureServer()
        
        // run read thread
        self.readThread.start()
    }
    
    // MARK: - Methods
    
    public func writeValue(_ value: Data, forCharacteristic handle: UInt16) {
        
        self.callback.writeDatabase?({ [weak self] (database) in
            
            guard let connection = self
                else { return }
            
            // update server with database from peripheral
            connection.server.database = database
            
            // modify database
            connection.server.writeValue(value, forCharacteristic: handle)
            
            // update peripheral database
            database = connection.server.database
        })
    }
    
    // MARK: - Private Methods
    
    private func configureServer() {
        
        // log
        server.log = { [unowned self] in self.callback.log?($0) }
        
        // wakeup ATT writer
        server.writePending = { [unowned self] in self.write() }
        
        server.willRead = { [unowned self] (uuid, handle, value, offset) in
            
            let request = GATTReadRequest(central: self.central,
                                          maximumUpdateValueLength: self.maximumUpdateValueLength,
                                          uuid: uuid,
                                          handle: handle,
                                          value: value,
                                          offset: offset)
            
            return self.callback.willRead?(request)
        }
        
        server.willWrite = { [unowned self] (uuid, handle, value, newValue) in
            
            let request = GATTWriteRequest(central: self.central,
                                           maximumUpdateValueLength: self.maximumUpdateValueLength,
                                           uuid: uuid,
                                           handle: handle,
                                           value: value,
                                           newValue: newValue)
            
            return self.callback.willWrite?(request)
        }
        
        server.didWrite = { [unowned self] (uuid, handle, newValue) in
            
            let confirmation = GATTWriteConfirmation(central: self.central,
                                                     maximumUpdateValueLength: self.maximumUpdateValueLength,
                                                     uuid: uuid,
                                                     handle: handle,
                                                     value: newValue)
            
            self.callback.didWrite?(confirmation)
        }
    }
    
    // IO error
    private func error(_ error: Error) {
        
        self.callback.log?("Disconnected \(error)")
        self.isRunning = false
        self.callback.didDisconnect?(error)
    }
    
    private func readMain() {
        
        guard self.isRunning
            else { sleep(1); return }
        
        guard let writeDatabase = self.callback.writeDatabase,
            let readConnection = self.callback.readConnection
            else { usleep(100); return }
        
        readConnection({ [weak self] in
            
            // write GATT DB serially
            writeDatabase({ [weak self] (database) in
                
                // update server with database from peripheral
                self?.server.database = database
            })
            
            // read incoming PDUs and may modify internal database
            do {
                
                guard let server = self?.server,
                    try server.read()
                    else { return }
            }
            catch {
                self?.error(error)
                return
            }
            
            // write GATT DB serially
            writeDatabase({ [weak self] (database) in
                
                // update peripheral database
                if let modifiedDatabase = self?.server.database {
                    
                    database = modifiedDatabase
                }
            })
        })
    }
    
    private func write() {
        
        // write outgoing PDU in the background.
        writeQueue.async { [weak self] in
            
            guard (self?.isRunning ?? false) else { sleep(1); return }
            
            do {
                
                /// write outgoing pending ATT PDUs
                var didWrite = false
                repeat { didWrite = try (self?.server.write() ?? false) }
                while didWrite && (self?.isRunning ?? false)
            }
            
            catch { self?.error(error) }
        }
    }
}

@available(OSX 10.12, *)
public struct GATTServerConnectionCallback {
    
    public var log: ((String) -> ())?
    
    public var willRead: ((GATTReadRequest<Central>) -> ATT.Error?)?
    
    public var willWrite: ((GATTWriteRequest<Central>) -> ATT.Error?)?
    
    public var didWrite: ((GATTWriteConfirmation<Central>) -> ())?
    
    public var writeDatabase: (((inout GATTDatabase) -> ()) -> ())?
    
    public var readConnection: ((() -> ()) -> ())?
    
    public var didDisconnect: ((Error) -> ())?
    
    fileprivate init() { }
}

#endif
