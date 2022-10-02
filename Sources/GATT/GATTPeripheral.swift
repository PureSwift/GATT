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
    
    /// Logging
    public var log: ((String) -> ())?
    
    public let hostController: HostController
    
    public let options: Options
    
    public var willRead: ((GATTReadRequest<Central>) async -> ATTError?)?
    
    public var willWrite: ((GATTWriteRequest<Central>) async -> ATTError?)?
    
    public var didWrite: ((GATTWriteConfirmation<Central>) async -> ())?
    
    public var activeConnections: Set<Central> {
        get async {
            return await Set(storage.connections.values.lazy.map { $0.central })
        }
    }
    
    private var socket: Socket?
    
    private var task: Task<(), Never>?
        
    private let storage = Storage()
    
    // MARK: - Initialization
    
    public init(
        hostController: HostController,
        options: Options = Options(),
        socket: Socket.Type
    ) {
        self.hostController = hostController
        self.options = options
    }
    
    deinit {
        if socket != nil {
            stop()
        }
    }
    
    // MARK: - Methods
    
    public func start() async throws {
        assert(socket == nil)
        // read address
        let address = try await hostController.readDeviceAddress()
        // enable advertising
        do { try await hostController.enableLowEnergyAdvertising() }
        catch HCIError.commandDisallowed { /* ignore */ }
        // create server socket
        let socket = try await Socket.lowEnergyServer(
            address: address,
            isRandom: false,
            backlog: 10
        )
        // start listening for connections
        self.socket = socket
        self.task = Task { [weak self] in
            self?.log?("Started GATT Server")
            do {
                while let socket = self?.socket, let self = self {
                    try Task.checkCancellation()
                    let newSocket = try await socket.accept()
                    self.log?("[\(newSocket.address)]: New connection")
                    await self.storage.newConnection(newSocket, options: options, delegate: self)
                }
            }
            catch _ as CancellationError { }
            catch {
                self?.log?("Error waiting for new connection: \(error)")
            }
        }
    }
    
    public func stop() {
        assert(socket != nil)
        self.socket = nil
        self.task?.cancel()
        self.task = nil
        self.log?("Stopped GATT Server")
    }
    
    public func add(service: BluetoothGATT.GATTAttribute.Service) async throws -> UInt16 {
        return await storage.add(service: service)
    }
    
    public func remove(service handle: UInt16) async {
        await storage.remove(service: handle)
    }
    
    public func removeAllServices() async {
        await storage.removeAllServices()
    }
    
    /// Modify the value of a characteristic, optionally emiting notifications if configured on active connections.
    public func write(_ newValue: Data, forCharacteristic handle: UInt16) async {
        await write(newValue, forCharacteristic: handle, ignore: .none)
    }
    
    /// Modify the value of a characteristic, optionally emiting notifications if configured on active connections.
    private func write(_ newValue: Data, forCharacteristic handle: UInt16, ignore central: Central? = nil) async {
        // write to master DB
        await storage.write(newValue, forAttribute: handle)
        // propagate changes to active connections
        let connections = await storage.connections
            .values
            .lazy
            .filter { $0.central != central }
        // update the DB of each connection, and send notifications concurrently
        await withTaskGroup(of: Void.self) { taskGroup in
            for connection in connections {
                taskGroup.addTask {
                    await connection.writeValue(newValue, forCharacteristic: handle)
                }
            }
        }
    }
    
    /// Read the value of the characteristic with specified handle.
    public subscript(characteristic handle: UInt16) -> Data {
        get async {
            return await storage.database[handle: handle].value
        }
    }
    
    /// Return the handles of the characteristics matching the specified UUID.
    public func characteristics(for uuid: BluetoothUUID) async -> [UInt16] {
        return await storage.database
            .lazy
            .filter { $0.uuid == uuid }
            .map { $0.handle }
    }
}

extension GATTPeripheral: GATTServerConnectionDelegate {
    
    func connection(_ central: Central, log message: String) {
        log?("[\(central)]: " + message)
    }
    
    func connection(_ central: Central, didDisconnect error: Swift.Error?) async {
        // try advertising again
        do { try await hostController.enableLowEnergyAdvertising() }
        catch HCIError.commandDisallowed { /* ignore */ }
        catch { log?("Could not enable advertising. \(error)") }
        // remove connection cache
        await storage.removeConnection(central)
        // log
        log?("[\(central)]: " + "Did disconnect. \(error?.localizedDescription ?? "")")
    }
    
    func connection(_ central: Central, willRead request: GATTReadRequest<Central>) async -> ATTError? {
        return await willRead?(request)
    }
    
    func connection(_ central: Central, willWrite request: GATTWriteRequest<Central>) async -> ATTError? {
        return await willWrite?(request)
    }
    
    func connection(_ central: Central, didWrite confirmation: GATTWriteConfirmation<Central>) async {
        // update DB and inform other connections
        await write(confirmation.value, forCharacteristic: confirmation.handle, ignore: confirmation.central)
        // notify delegate
        await didWrite?(confirmation)
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

internal extension GATTPeripheral {
    
    actor Storage {
        
        var database = GATTDatabase()
        
        var connections = [Central: GATTServerConnection<Socket>](minimumCapacity: 2)
                
        fileprivate init() { }
        
        func add(service: BluetoothGATT.GATTAttribute.Service) -> UInt16 {
            return database.add(service: service)
        }
        
        func remove(service handle: UInt16) {
            database.remove(service: handle)
        }
        
        func removeAllServices() {
            database.removeAll()
        }
        
        func write(_ value: Data, forAttribute handle: UInt16) {
            database.write(value, forAttribute: handle)
        }
        
        func newConnection(
            _ socket: Socket,
            options: Options,
            delegate: GATTServerConnectionDelegate
        ) async {
            let central = Central(id: socket.address)
            connections[central] = await GATTServerConnection(
                central: central,
                socket: socket,
                maximumTransmissionUnit: options.maximumTransmissionUnit,
                maximumPreparedWrites: options.maximumPreparedWrites,
                database: database,
                delegate: delegate
            )
        }
        
        func removeConnection(_ central: Central) {
            self.connections[central] = nil
        }
    }
}

#endif
