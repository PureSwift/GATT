//
//  GATTPeripheral.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 7/18/18.
//

import Foundation
import Bluetooth

@available(OSX 10.12, *)
public final class GATTPeripheral <HostController: BluetoothHostControllerInterface, L2CAPSocket: L2CAPSocketProtocol>: PeripheralProtocol {
    
    // MARK: - Properties
    
    public var log: ((String) -> ())?
    
    public let options: Options
    
    public let controller: HostController
    
    public var willRead: ((GATTReadRequest<Central>) -> ATT.Error?)?
    
    public var willWrite: ((GATTWriteRequest<Central>) -> ATT.Error?)?
    
    public var didWrite: ((GATTWriteConfirmation<Central>) -> ())?
    
    public var newConnection: (() throws -> (socket: L2CAPSocket, central: Central))?
    
    // MARK: - Private Properties
    
    internal lazy var databaseQueue: DispatchQueue = DispatchQueue(label: "\(type(of: self)) Database Queue")
    
    private var database = GATTDatabase()
    
    private var isServerRunning = false
    
    private var serverThread: Thread?
    
    private var connections = [UInt: GATTServerConnection<L2CAPSocket>]()
    
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
        
        /*
         let serverSocket = try L2CAPSocket.lowEnergyServer(controllerAddress: controller.address,
         isRandom: false,
         securityLevel: .low)
         */
        
        isServerRunning = true
        
        log?("Started GATT Server")
        
        let serverThread = Thread { [weak self] in self?.main() }
        
        self.serverThread = serverThread
        
        serverThread.start()
    }
    
    public func stop() {
        
        guard isServerRunning else { return }
        
        self.isServerRunning = false
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
        
        while isServerRunning, let newConnection = self.newConnection {
            
            do {
                
                let (newSocket, central) = try newConnection()
                
                guard isServerRunning else { return }
                
                log?("[\(central)]: New connection")
                
                let connectionIdentifier = newConnectionID()
                let connection = GATTServerConnection(central: central,
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
        catch { log?("Could not enable advertising. \(error)") }
    }
    
    private func writeDatabase <T> (_ block: (inout GATTDatabase) -> (T)) -> T {
        
        return databaseQueue.sync { block(&self.database) }
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
