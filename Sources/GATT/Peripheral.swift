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
    
    public let identifier: Int
    
    public let central: Central
    
    public var callback = Callback()
    
    internal let server: GATTServer
    
    internal private(set) var isRunning: Bool = true
    
    internal private(set) var isReading: Bool = false
    
    private lazy var thread: Thread = Thread { [weak self] in
        
        // run until object is released
        while let connection = self {
            
            // run the main loop exactly once.
            self?.main()
        }
    }
    
    internal lazy var readQueue: DispatchQueue = DispatchQueue(label: "\(type(of: self)) \(self.identifier) Read Queue")
    
    internal lazy var writeQueue: DispatchQueue = DispatchQueue(label: "\(type(of: self)) \(self.identifier) Write Queue")
    
    internal var maximumUpdateValueLength: Int {
        
        // ATT_MTU-3
        return Int(server.maximumTransmissionUnit.rawValue) - 3
    }
    
    public init(central: Central,
                socket: L2CAPSocketProtocol,
                maximumTransmissionUnit: ATTMaximumTransmissionUnit,
                maximumPreparedWrites: Int) {
        
        self.central = central
        self.server = GATTServer(socket: socket,
                                 maximumTransmissionUnit: maximumTransmissionUnit,
                                 maximumPreparedWrites: maximumPreparedWrites)
        
        // setup callbacks
        server.log = { [unowned self] in self.callback.log?("[\(self.central)]: " + $0) }
        
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
        
        
    }
    
    private func main() {
        
        guard self.isRunning else { sleep(1); return }
        
        readQueue.async { [weak self] in
            
            guard self?.isReading == false else { return }
            
            self?.isReading = true
            
            do {
                
                if let connection = self, let database = connection.callback?.willWriteDatabase?() {
                    
                    self?.server.database = database
                }
                
                try self.server.read()
                
                self.callback.didWriteDatabase?(self.server.database)
            }
                
            catch { self.error(error) }
        }
        
        if isReading == false {
            
            
        }
        
        readQueue.async {
            
            do {
                
                if let database = self.callback.willWriteDatabase?() {
                    
                    self.server.database = database
                }
                
                try self.server.read()
                
                self.callback.didWriteDatabase?(self.server.database)
            }
            
            catch { self.error(error) }
        }
        
        do {
            
            if let database = self.callback.willWriteDatabase?() {
                
                self.server.database = database
            }
            
            try server.read()
            
            self.callback.didWriteDatabase?(self.server.database)
            
            peripheral.database = server.database
            
            /// write outgoing pending ATT PDUs
            var didWrite = false
            repeat { didWrite = try server.write() }
                while didWrite
        }
            
        catch {
            
            peripheral.log?("[\(central)]: Disconnected \(error)")
            
            do { try peripheral.controller.enableLowEnergyAdvertising() }
            catch HCIError.commandDisallowed { /* ignore */ }
            catch { fatalError("Could not enable advertising.") }
        }
    }
}

public extension GATTServerConnection {
    
    public struct Callback {
        
        public var log: ((String) -> ())?
        
        public var willRead: ((GATTReadRequest<Central>) -> ATT.Error?)?
        
        public var willWrite: ((GATTWriteRequest<Central>) -> ATT.Error?)?
        
        public var didWrite: ((GATTWriteConfirmation<Central>) -> ())?
        
        public var willWriteDatabase: (() -> (GATTDatabase))?
        
        public var didWriteDatabase: ((GATTDatabase) -> ())?
        
        public var didDisconnect: () -> ()
        
        fileprivate init() { }
    }
}

public final class GATTServerConnectionOLD {
    
    public let identifier: Int
    
    public let central: Central
    
    let server: GATTServer
    
    
    
    private(set) weak var peripheral: GATTPeripheral!
    
    private var maximumUpdateValueLength: Int {
        
        // ATT_MTU-3
        return Int(server.maximumTransmissionUnit.rawValue) - 3
    }
    
    init(socket: L2CAPSocket, peripheral: GATTPeripheral) {
        
        // initialize
        self.peripheral = peripheral
        self.connectionID = peripheral.newConnectionID()
        self.central = Central(socket: socket)
        self.server = GATTServer(socket: socket,
                                 maximumTransmissionUnit: peripheral.options.maximumTransmissionUnit,
                                 maximumPreparedWrites: peripheral.options.maximumPreparedWrites)
        
        // start running
        server.database = peripheral.database
        server.log = { [unowned self] in self.peripheral.log?("[\(self.central)]: " + $0) }
        
        server.willRead = { [unowned self] (uuid, handle, value, offset) in
            
            let request = GATTReadRequest(central: self.central,
                                          maximumUpdateValueLength: self.maximumUpdateValueLength,
                                          uuid: uuid,
                                          handle: handle,
                                          value: value,
                                          offset: offset)
            
            return self.peripheral.willRead?(request)
        }
        
        server.willWrite = { [unowned self] (uuid, handle, value, newValue) in
            
            let request = GATTWriteRequest(central: self.central,
                                           maximumUpdateValueLength: self.maximumUpdateValueLength,
                                           uuid: uuid,
                                           handle: handle,
                                           value: value,
                                           newValue: newValue)
            
            return self.peripheral.willWrite?(request)
        }
        
        server.didWrite = { [unowned self] (uuid, handle, newValue) in
            
            let confirmation = GATTWriteConfirmation(central: self.central,
                                                     maximumUpdateValueLength: self.maximumUpdateValueLength,
                                                     uuid: uuid,
                                                     handle: handle,
                                                     value: newValue)
            
            self.peripheral.didWrite?(confirmation)
        }
        
        thread.start()
    }
    
    private func main() {
        
        while let peripheral = self.peripheral, peripheral.isServerRunning {
            
            do {
                
                server.database = peripheral.database
                
                try server.read()
                
                peripheral.database = server.database
                
                /// write outgoing pending ATT PDUs
                var didWrite = false
                repeat { didWrite = try server.write() }
                while didWrite
            }
                
            catch {
                
                peripheral.log?("[\(central)]: Disconnected \(error)")
                
                do { try peripheral.controller.enableLowEnergyAdvertising() }
                catch HCIError.commandDisallowed { /* ignore */ }
                catch { fatalError("Could not enable advertising.") }
                
                break // end while loop
            }
        }
        
        // remove from peripheral
        guard let index = self.peripheral?.connections.index(where: { $0.connectionID == connectionID })
            else { return }
        
        self.peripheral?.connections.remove(at: index)
    }
}

@available(OSX 10.12, *)
public final class GATTPeripheral: PeripheralProtocol {
    
    // MARK: - Properties
    
    public var log: ((String) -> ())?
    
    public let options: Options
    
    public let controller: BluetoothHostControllerInterface
    
    public var willRead: ((GATTReadRequest<Central>) -> ATT.Error?)?
    
    public var willWrite: ((GATTWriteRequest<Central>) -> ATT.Error?)?
    
    public var didWrite: ((GATTWriteConfirmation<Central>) -> ())?
    
    // MARK: - Private Properties
    
    fileprivate var database = GATTDatabase()
    
    fileprivate var isServerRunning = false
    
    fileprivate var serverSocket: L2CAPSocketProtocol?
    
    fileprivate var serverThread: Thread?
    
    fileprivate var connections = [Connection]()
    
    private var lastConnectionID = 0
    
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
        
        return database.filter { $0.uuid == uuid }.map { $0.handle }
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
                
                let connection = Connection(socket: newSocket, peripheral: self)
                
                connections.append(connection)
            }
                
            catch { log?("Error waiting for new connection: \(error)") }
        }
        
        log?("Stopped GATT Server")
    }
    
    fileprivate func newConnectionID() -> Int {
        
        lastConnectionID += 1
        
        return lastConnectionID
    }
    
    // MARK: Subscript
    
    public subscript(characteristic handle: UInt16) -> Data {
        
        get { return database[handle: handle].value }
        
        set { connections.forEach { $0.server.writeValue(newValue, forCharacteristic: handle) } }
    }
}

@available(OSX 10.12, *)
public extension GATTPeripheral {
    
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
public extension GATTPeripheral {
    
    /// Central Peer
    ///
    /// Represents a remote central device that has connected to an app implementing the peripheral role on a local device.
    public struct Central: Peer {
        
        public let identifier: Bluetooth.Address
    }
}

@available(OSX 10.12, *)
private extension GATTPeripheral {
    
    final class Connection {
        
        let connectionID: Int
        
        let central: Central
        
        let server: GATTServer
        
        lazy var thread: Thread = Thread { [weak self] in self?.main() }
        
        private(set) weak var peripheral: GATTPeripheral!
        
        private var maximumUpdateValueLength: Int {
            
            // ATT_MTU-3
            return Int(server.maximumTransmissionUnit.rawValue) - 3
        }
        
        init(socket: L2CAPSocket, peripheral: GATTPeripheral) {
            
            // initialize
            self.peripheral = peripheral
            self.connectionID = peripheral.newConnectionID()
            self.central = Central(socket: socket)
            self.server = GATTServer(socket: socket,
                                     maximumTransmissionUnit: peripheral.options.maximumTransmissionUnit,
                                     maximumPreparedWrites: peripheral.options.maximumPreparedWrites)
            
            // start running
            server.database = peripheral.database
            server.log = { [unowned self] in self.peripheral.log?("[\(self.central)]: " + $0) }
            
            server.willRead = { [unowned self] (uuid, handle, value, offset) in
                
                let request = GATTReadRequest(central: self.central,
                                              maximumUpdateValueLength: self.maximumUpdateValueLength,
                                              uuid: uuid,
                                              handle: handle,
                                              value: value,
                                              offset: offset)
                
                return self.peripheral.willRead?(request)
            }
            
            server.willWrite = { [unowned self] (uuid, handle, value, newValue) in
                
                let request = GATTWriteRequest(central: self.central,
                                               maximumUpdateValueLength: self.maximumUpdateValueLength,
                                               uuid: uuid,
                                               handle: handle,
                                               value: value,
                                               newValue: newValue)
                
                return self.peripheral.willWrite?(request)
            }
            
            server.didWrite = { [unowned self] (uuid, handle, newValue) in
                
                let confirmation = GATTWriteConfirmation(central: self.central,
                                                         maximumUpdateValueLength: self.maximumUpdateValueLength,
                                                         uuid: uuid,
                                                         handle: handle,
                                                         value: newValue)
                
                self.peripheral.didWrite?(confirmation)
            }
            
            thread.start()
        }
        
        private func main() {
            
            while let peripheral = self.peripheral, peripheral.isServerRunning {
                
                do {
                    
                    server.database = peripheral.database
                    
                    try server.read()
                    
                    peripheral.database = server.database
                    
                    /// write outgoing pending ATT PDUs
                    var didWrite = false
                    repeat { didWrite = try server.write() }
                        while didWrite
                }
                    
                catch {
                    
                    peripheral.log?("[\(central)]: Disconnected \(error)")
                    
                    do { try peripheral.controller.enableLowEnergyAdvertising() }
                    catch HCIError.commandDisallowed { /* ignore */ }
                    catch { fatalError("Could not enable advertising.") }
                    
                    break // end while loop
                }
            }
            
            // remove from peripheral
            guard let index = self.peripheral?.connections.index(where: { $0.connectionID == connectionID })
                else { return }
            
            self.peripheral?.connections.remove(at: index)
        }
    }
}
