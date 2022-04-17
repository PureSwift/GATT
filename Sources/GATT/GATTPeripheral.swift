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
public final class GATTPeripheral <HostController: BluetoothHostControllerInterface, Socket: L2CAPSocket>: PeripheralManager {
        
    /// Central Peer
    public typealias Central = GATT.Central
    
    /// Peripheral Options
    public typealias Options = GATTPeripheralOptions
    
    // MARK: - Properties
    
    public let hostController: HostController
    
    public let options: Options
    
    public var willRead: ((GATTReadRequest<Central>) -> ATTError?)?
    
    public var willWrite: ((GATTWriteRequest<Central>) -> ATTError?)?
    
    public var didWrite: ((GATTWriteConfirmation<Central>) -> ())?
    
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
                while let socket = self?.socket {
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
    
    /// Modify the value of a characteristic, optionally emiting notifications if configured on active connections.
    public func write(_ newValue: Data, forCharacteristic handle: UInt16) async {
        await write(newValue, forCharacteristic: handle, ignore: .none)
    }
    
    /// Modify the value of a characteristic, optionally emiting notifications if configured on active connections.
    private func write(_ newValue: Data, forCharacteristic handle: UInt16, ignore central: Central? = nil) async {
        // write to master DB
        database.write(newValue, forAttribute: handle)
        // propagate changes to active connections
        let connections = self.connections
            .values
            .lazy
            .filter { $0.central != central }
        for connection in connections {
            await connection.writeValue(newValue, forCharacteristic: handle)
        }
    }
    
    // MARK: - Subscript
    
    public subscript(characteristic handle: UInt16) -> Data {
        // TODO: Make async safe
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
    
    func connection(_ central: Central, log message: String) {
        self.log?("[\(central)]: " + message)
    }
    
    func connection(_ central: Central, didDisconnect error: Swift.Error?) {
        return
    }
    
    func connection(_ central: Central, willRead request: GATTReadRequest<Central>) -> ATTError? {
        return willRead?(request)
    }
    
    func connection(_ central: Central, willWrite request: GATTWriteRequest<Central>) -> ATTError? {
        return willWrite?(request)
    }
    
    func connection(_ central: Central, didWrite confirmation: GATTWriteConfirmation<Central>) async {
        // update DB and inform other connections
        await write(confirmation.value, forCharacteristic: confirmation.handle, ignore: confirmation.central)
        // notify delegate
        didWrite?(confirmation)
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
