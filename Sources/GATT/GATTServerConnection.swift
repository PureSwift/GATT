//
//  Peripheral.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 7/17/18.
//

import Foundation
import Bluetooth

public final class GATTServerConnectionManager <HostCon> {
    
    // MARK: - Properties
    
    public var log: ((String) -> ())?
    
    public let options: Options
    
    public let controller: BluetoothHostControllerInterface
    
    public var willRead: ((GATTReadRequest<Central>) -> ATT.Error?)?
    
    public var willWrite: ((GATTWriteRequest<Central>) -> ATT.Error?)?
    
    public var didWrite: ((GATTWriteConfirmation<Central>) -> ())?
    
    // MARK: - Private Properties
    
    internal lazy var databaseQueue: DispatchQueue = DispatchQueue(label: "\(type(of: self)) Database Queue")
    
    private var database = GATTDatabase()
    
    private var isServerRunning = false
    
    private var serverSocket: L2CAPSocket?
    
    private var serverThread: Thread?
    
    private var connections = [UInt: GATTServerConnection]()
    
    private var lastConnectionID: UInt = 0
    
    // MARK: - Initialization
    
    public init(controller: HostController,
                options: Options = Options()) {
        
        self.controller = controller
        self.options = options
    }
    
    // MARK: - Methods
    
    public func start() throws {
        
        guard isServerRunning == false else { return }
        
        // enable advertising
        do { try controller.enableLowEnergyAdvertising() }
        catch HCIError.commandDisallowed { /* ignore */ }
        
        let serverSocket = try L2CAPSocket.lowEnergyServer(controllerAddress: controller.address,
                                                           isRandom: false,
                                                           securityLevel: .low)
        
        isServerRunning = true
        
        log?("Started GATT Server")
        
        let serverThread = Thread { [weak self] in self?.main() }
        
        self.serverSocket = serverSocket
        self.serverThread = serverThread
        
        serverThread.start()
    }
    
    public func stop() {
        
        guard isServerRunning else { return }
        
        isServerRunning = false
        
        self.serverSocket = nil
        self.serverThread = nil
    }
    
    public func add(service: GATT.Service) throws -> UInt16 {
        
        return database.add(service: service)
    }
    
    public func remove(service handle: UInt16) {
        
        database.remove(service: handle)
    }
    
    public func removeAllServices() {
        
        database.removeAll()
    }
    
    /// Return the handles of the characteristics matching the specified UUID.
    public func characteristics(for uuid: BluetoothUUID) -> [UInt16] {
        
        return database
            .filter { $0.uuid == uuid }
            .map { $0.handle }
    }
    
    // MARK: - Subscript
    
    public subscript(characteristic handle: UInt16) -> Data {
        
        get { return writeDatabase { $0[handle: handle].value } }
        
        set { connections.values.forEach { $0.writeValue(newValue, forCharacteristic: handle) } }
    }
    
    // MARK: - Private Methods
    
    private func main() {
        
        guard let serverSocket = self.serverSocket
            else { fatalError("No server socket") }
        
        while isServerRunning {
            
            do {
                
                let newSocket = try serverSocket.waitForConnection()
                
                guard isServerRunning else { return }
                
                log?("[\(newSocket.address)]: New \(newSocket.addressType) connection")
                
                let connectionIdentifier = newConnectionID()
                let connection = GATTServerConnection(central: Central(socket: newSocket),
                                                      socket: newSocket,
                                                      maximumTransmissionUnit: options.maximumTransmissionUnit,
                                                      maximumPreparedWrites: options.maximumPreparedWrites)
                
                connection.callback.log? = { [unowned self] in self.log?("[\(connection.central)]: " + $0) }
                connection.callback.didWrite = { [unowned self] in self.didWrite?($0) }
                connection.callback.willWrite = { [unowned self] in self.willWrite?($0) }
                connection.callback.willRead = { [unowned self] in self.willRead?($0) }
                connection.callback.writeDatabase = { [unowned self] in self.writeDatabase($0) }
                connection.callback.didDisconnect = { [unowned self] in self.disconnect(connectionIdentifier, error: $0) }
                
                self.connections[connectionIdentifier] = connection
            }
                
            catch { log?("Error waiting for new connection: \(error)") }
        }
        
        log?("Stopped GATT Server")
    }
    
    private func newConnectionID() -> UInt {
        
        lastConnectionID += 1
        
        return lastConnectionID
    }
    
    private func disconnect(_ connection: UInt, error: Error) {
        
        // remove from peripheral, release and close socket
        connections[connection] = nil
        
        // enable LE advertising
        do { try controller.enableLowEnergyAdvertising() }
        catch HCIError.commandDisallowed { /* ignore */ }
        catch { fatalError("Could not enable advertising.") }
    }
    
    private func writeDatabase <T> (_ block: (inout GATTDatabase) -> (T)) -> T {
        
        return databaseQueue.sync { block(&self.database) }
    }
}

public extension GATTServerConnectionManager {
    
    public struct Options {
        
        public let maximumTransmissionUnit: ATTMaximumTransmissionUnit
        
        public let maximumPreparedWrites: Int
        
        public init(maximumTransmissionUnit: ATTMaximumTransmissionUnit = .default,
                    maximumPreparedWrites: Int = 100) {
            
            self.maximumTransmissionUnit = maximumTransmissionUnit
            self.maximumPreparedWrites = maximumPreparedWrites
        }
    }
}

@available(OSX 10.12, *)
public extension GATTServerConnection {
    
    /// Central Peer
    ///
    /// Represents a remote central device that has connected to an app implementing the peripheral role on a local device.
    public struct Central: Peer {
        
        public let identifier: Bluetooth.Address
        
        internal init(identifier: Bluetooth.Address) {
            
            self.identifier = identifier
        }
    }
}

@available(OSX 10.12, *)
public final class GATTServerConnection {
    
    // MARK: - Properties
    
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
    
    internal lazy var writeQueue: DispatchQueue = DispatchQueue(label: "\(type(of: self)) \(self.central) Write Queue")
    
    internal var maximumUpdateValueLength: Int {
        
        // ATT_MTU-3
        return Int(server.maximumTransmissionUnit.rawValue) - 3
    }
    
    // MARK: - Initialization
    
    public init(central: Central,
                socket: L2CAPSocketProtocol,
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
            server.writeValue(value, forCharacteristic: handle)
            
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
        
        guard let writeDatabase = self.callback.writeDatabase
            else { usleep(100); return }
        
        // write GATT DB serially
        writeDatabase({ [weak self] (database) in
            
            guard let connection = self
                else { return }
            
            do {
                
                // update server with database from peripheral
                connection.server.database = database
                
                // read incoming PDUs and may modify database
                try connection.server.read()
                
                // update peripheral database
                database = connection.server.database
            }
            
            catch { connection.error(error) }
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
public extension GATTServerConnection {
    
    public struct Callback {
        
        public var log: ((String) -> ())?
        
        public var willRead: ((GATTReadRequest<Central>) -> ATT.Error?)?
        
        public var willWrite: ((GATTWriteRequest<Central>) -> ATT.Error?)?
        
        public var didWrite: ((GATTWriteConfirmation<Central>) -> ())?
        
        public var writeDatabase: (((inout GATTDatabase) -> ()) -> ())?
        
        public var didDisconnect: ((Error) -> ())?
        
        fileprivate init() { }
    }
}
