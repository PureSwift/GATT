//
//  GATTPeripheral.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 7/18/18.
//

#if canImport(BluetoothGATT) && canImport(BluetoothHCI)
import Foundation
@_exported import Bluetooth
@_exported import BluetoothGATT
@_exported import BluetoothHCI

/// GATT Peripheral Manager
public actor GATTPeripheral <HostController: BluetoothHostControllerInterface, Socket: L2CAPSocket> /* : PeripheralManager */ {
    
    /// Peripheral Options
    public typealias Options = GATTPeripheralOptions
        
    // MARK: - Properties
    
    public let hostController: HostController
    
    public let options: GATTPeripheralOptions
    
    private var socket: Socket?
    
    private var task: Task<(), Never>?
        
    public var activeConnections: [Central] {
        self.connections.values.map { $0.central }
    }
    
    internal private(set) var database = GATTDatabase()
        
    internal private(set) var connections = [UInt: GATTServerConnection<Socket>]()
        
    private var lastConnectionID: UInt = 0
    
    // MARK: - Initialization
    
    public init(
        hostController: HostController,
        options: GATTPeripheralOptions = GATTPeripheralOptions(),
        socket: Socket.Type
    ) {
        self.hostController = hostController
        self.options = options
    }
    
    deinit {
        stop()
    }
    
    // MARK: - Methods
    
    public func start() async throws {
        // read address
        let address = try await hostController.readDeviceAddress()
        // enable advertising
        do { try await hostController.enableLowEnergyAdvertising() }
        catch HCIError.commandDisallowed { /* ignore */ }
        // create server socket
        let socket = try Socket.lowEnergyServer(
            address: address,
            isRandom: false,
            backlog: 10
        )
        // start listening for connections
        self.socket = socket
        self.task = Task { [weak self] in
            log("Started GATT Server")
            do {
                while let socket = await self?.socket {
                    try Task.checkCancellation()
                    let newSocket = try await socket.accept()
                    await self?.newConnection(newSocket)
                }
            }
            catch _ as CancellationError { }
            catch {
                log("Error waiting for new connection: \(error)")
                return
            }
        }
    }
    
    public func stop() {
        self.socket = nil
        self.task?.cancel()
        self.task = nil
        log("Stopped GATT Server")
    }
    
    public func add(service: BluetoothGATT.GATTAttribute.Service) throws -> UInt16 {
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
        
        return writeDatabase { $0.filter { $0.uuid == uuid }.map { $0.handle } }
    }
    
    // MARK: - Subscript
    
    public subscript(characteristic handle: UInt16) -> Data {
        
        get { return writeDatabase { $0[handle: handle].value } }
        
        set {
            writeDatabase { $0.write(newValue, forAttribute: handle) }
            connectionsQueue
                .sync { [unowned self] in self.connections.values }
                .forEach { $0.writeValue(newValue, forCharacteristic: handle) }
        }
    }
    
    // MARK: - Private Methods
    
    private func newConnection(_ socket: Socket) async {
        let central = Central(id: socket.address)
        let id = newConnectionID()
        self.connections[id] = GATTServerConnection(
            central: central,
            socket: socket,
            maximumTransmissionUnit: options.maximumTransmissionUnit,
            maximumPreparedWrites: options.maximumPreparedWrites,
            delegate: self
        )
    }
    
    private func log(_ message: String) {
        
    }
    
    private func main() {
        
        // wait for new connections
        while isServerRunning, let newConnection = self.newConnection {
            
            do {
                
                let (newSocket, central) = try newConnection()
                
                guard isServerRunning else { return }
                
                let connectionIdentifier = newConnectionID()
                let connection = GATTServerConnection(central: central,
                                                      socket: newSocket,
                                                      maximumTransmissionUnit: options.maximumTransmissionUnit,
                                                      maximumPreparedWrites: options.maximumPreparedWrites)
                
                connection.callback.log = { [unowned self] in self.log?("[\(connection.central)]: " + $0) }
                connection.callback.didWrite = { [unowned self] (write) in
                    
                    // notify other connected centrals
                    self.connectionsQueue.sync { [unowned self] in
                        self.connections.values.forEach {
                            if $0.central != write.central {
                                $0.writeValue(write.value, forCharacteristic: write.handle)
                            }
                        }
                    }
                    
                    self.didWrite?(write) // notify delegate
                }
                connection.callback.willWrite = { [unowned self] in self.willWrite?($0) }
                connection.callback.willRead = { [unowned self] in self.willRead?($0) }
                connection.callback.writeDatabase = { [unowned self] in self.writeDatabase($0) }
                connection.callback.readConnection = { [unowned self] in self.readConnection($0) }
                connection.callback.didDisconnect = { [unowned self] in self.disconnect(connectionIdentifier, error: $0) }
                
                // hold strong reference to connection
                connectionsQueue.sync { [unowned self] in
                    self.connections[connectionIdentifier] = connection
                }
            }
                
            catch { log("Error waiting for new connection: \(error)") }
        }
        
        log("Stopped GATT Server")
    }
    
    private func newConnectionID() -> UInt {
        lastConnectionID += 1
        return lastConnectionID
    }
    
    private func disconnect(_ connection: UInt, error: Error) async {
        // remove from peripheral, release and close socket
        self.connections[connection] = nil
        // enable LE advertising
        do { try await hostController.enableLowEnergyAdvertising() }
        catch HCIError.commandDisallowed { /* ignore */ }
        catch { log("Could not enable advertising. \(error)") }
    }
}

public struct GATTPeripheralOptions {
    
    public let maximumTransmissionUnit: ATTMaximumTransmissionUnit
    
    public let maximumPreparedWrites: Int
    
    public init(maximumTransmissionUnit: ATTMaximumTransmissionUnit = .max,
                maximumPreparedWrites: Int = 100) {
        
        self.maximumTransmissionUnit = maximumTransmissionUnit
        self.maximumPreparedWrites = maximumPreparedWrites
    }
}

#endif
