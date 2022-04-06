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
    
    public var activeConnections: [Central] {
        self.connections.values.map { $0.central }
    }
    
    private var socket: Socket?
    
    private var task: Task<(), Never>?
    
    private let log: ((String) -> ())?
    
    private var database = GATTDatabase()
        
    private var connections = [UInt: GATTServerConnection<Socket>]()
        
    private var lastConnectionID: UInt = 0
    
    // MARK: - Initialization
    
    public init(
        hostController: HostController,
        options: GATTPeripheralOptions = GATTPeripheralOptions(),
        socket: Socket.Type,
        log: ((String) -> ())? = nil
    ) {
        self.hostController = hostController
        self.options = options
        self.log = log
    }
    
    deinit {
        if socket != nil {
            stop()
        }
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
            self?.log?("Started GATT Server")
            do {
                while let socket = await self?.socket {
                    try Task.checkCancellation()
                    let newSocket = try await socket.accept()
                    await self?.newConnection(newSocket)
                }
            }
            catch _ as CancellationError { }
            catch {
                self?.log?("Error waiting for new connection: \(error)")
            }
        }
    }
    
    public func stop() {
        self.socket = nil
        self.task?.cancel()
        self.task = nil
        self.log?("Stopped GATT Server")
    }
    
    public func add(service: BluetoothGATT.GATTAttribute.Service) throws -> UInt16 {
        return database.add(service: service) // TODO: mutate while running
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
            .lazy
            .filter { $0.uuid == uuid }
            .map { $0.handle }
    }
    
    /// Modify the value of a characteristic, optionally emiting notifications if configured on active connections.
    public func write(_ newValue: Data, forCharacteristic handle: UInt16) async {
        database.write(newValue, forAttribute: handle)
        for connection in self.connections.values {
            await connection.writeValue(newValue, forCharacteristic: handle)
        }
    }
    
    // MARK: - Subscript
    
    public subscript(characteristic handle: UInt16) -> Data {
        database[handle: handle].value
    }
    
    // MARK: - Private Methods
    
    private func newConnection(_ socket: Socket) async {
        let central = Central(id: socket.address)
        let id = newConnectionID()
        self.connections[id] = await GATTServerConnection(
            central: central,
            socket: socket,
            maximumTransmissionUnit: options.maximumTransmissionUnit,
            maximumPreparedWrites: options.maximumPreparedWrites,
            delegate: self
        )
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
        catch { log?("Could not enable advertising. \(error)") }
    }
}

extension GATTPeripheral: GATTServerConnectionDelegate {
    
    nonisolated func connection(_ central: Central, log message: String) async {
        self.log("[\(connection.central)]: " + message)
    }
    
    func connection(_ central: Central, didDisconnect error: Error?) async {
        self.connections.values.forEach {
            if $0.central != write.central {
                $0.writeValue(write.value, forCharacteristic: write.handle)
            }
        }
    }
    
    func connection(_ central: Central, willRead request: GATTReadRequest<Central>) -> ATTError? {
        
    }
    
    func connection(_ central: Central, willWrite request: GATTWriteRequest<Central>) -> ATTError? {
        
    }
    
    func connection(_ central: Central, didWrite confirmation: GATTWriteConfirmation<Central>) {
        
    }
    
    func connection(_ central: Central, access database: inout GATTDatabase) {
        
    }
}

// MARK: - Supporting Types

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
