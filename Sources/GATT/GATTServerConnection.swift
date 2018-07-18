//
//  Peripheral.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 7/17/18.
//

import Foundation
import Bluetooth

@available(OSX 10.12, *)
public final class GATTServerConnection <Central: Peer> {
    
    // MARK: - Properties
    
    public let identifier: Int
    
    public let central: Central
    
    public var callback = Callback()
    
    internal let server: GATTServer
    
    internal private(set) var isRunning: Bool = true
    
    private lazy var readThread: Thread = Thread { [weak self] in
        
        // run until object is released
        while let connection = self {
            
            // run the main loop exactly once.
            self?.readMain()
        }
    }
    
    internal lazy var writeQueue: DispatchQueue = DispatchQueue(label: "\(type(of: self)) \(self.identifier) Write Queue")
    
    internal var maximumUpdateValueLength: Int {
        
        // ATT_MTU-3
        return Int(server.maximumTransmissionUnit.rawValue) - 3
    }
    
    // MARK: - Initialization
    
    public init(identifier: Int,
                central: Central,
                socket: L2CAPSocketProtocol,
                maximumTransmissionUnit: ATTMaximumTransmissionUnit,
                maximumPreparedWrites: Int) {
        
        self.identifier = identifier
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
        
        server.writeValue(value, forCharacteristic: handle)
    }
    
    // MARK: - Private Methods
    
    private func configureServer() {
        
        server.log = { [unowned self] in self.callback.log?("[\(self.central)]: " + $0) }
        
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
        
        self.callback.log?("[\(central)]: Disconnected \(error)")
        self.callback.didDisconnect?(error)
    }
    
    private func readMain() {
        
        guard self.isRunning else { sleep(1); return }
        
        do {
            
            if let database = self.callback.willWriteDatabase?() {
                
                self.server.database = database
            }
            
            try self.server.read()
            
            self.callback.didWriteDatabase?(self.server.database)
        }
            
        catch { self.error(error) }
    }
    
    private func write() {
        
        // write outgoing PDU in the background.
        writeQueue.async { [weak self] in
            
            do {
                
                /// write outgoing pending ATT PDUs
                var didWrite = false
                repeat { didWrite = try self?.server.write() ?? false }
                while didWrite && (self?.isRunning ?? false)
            }
            
            catch { self?.error(error) }
        }
    }
}

@available(OSX 10.12, *)
public extension GATTServerConnection {
    
    public struct Callback {
        
        public var log: ((String) -> ())?
        
        public var willRead: ((GATTReadRequest<Central>) -> ATT.Error?)?
        
        public var willWrite: ((GATTWriteRequest<Central>) -> ATT.Error?)?
        
        public var didWrite: ((GATTWriteConfirmation<Central>) -> ())?
        
        public var willWriteDatabase: (() -> (GATTDatabase))?
        
        public var didWriteDatabase: ((GATTDatabase) -> ())?
        
        public var didDisconnect: ((Error) -> ())?
        
        fileprivate init() { }
    }
}
