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
public final class GATTPeripheral <HostController: BluetoothHostControllerInterface, Socket: L2CAPServer>: PeripheralManager, @unchecked Sendable where Socket: Sendable, HostController: Sendable {
    
    /// Central Peer
    public typealias Central = GATT.Central
    
    /// Peripheral Options
    public typealias Options = GATTPeripheralOptions
    
    /// Peripheral Advertising Options
    public typealias AdvertisingOptions = GATTPeripheralAdvertisingOptions
    
    public typealias Data = Socket.Connection.Data
    
    // MARK: - Properties
    
    /// Logging
    public var log: (@Sendable (String) -> ())?
    
    public let hostController: HostController
    
    public let options: Options
    
    public var willRead: ((GATTReadRequest<Central, Data>) -> ATTError?)?
    
    public var willWrite: ((GATTWriteRequest<Central, Data>) -> ATTError?)?
    
    public var didWrite: ((GATTWriteConfirmation<Central, Data>) async -> ())?
    
    public var connections: Set<Central> {
        get async {
            return await Set(storage.connections.values.lazy.map { $0.central })
        }
    }
    
    public var isAdvertising: Bool {
        get async {
            return await storage.isAdvertising
        }
    }
        
    private let storage: Storage
    
    private var maximumUpdateValueLength = [Central: Int]()
    
    private let lock = NSLock()
    
    // MARK: - Initialization
    
    public init(
        hostController: HostController,
        options: Options = Options(),
        socket: Socket.Type
    ) {
        self.hostController = hostController
        self.options = options
        self.storage = .init(
            hostController: hostController,
            options: options
        )
    }
    
    deinit {
        let storage = self.storage
        Task {
            if await storage.isAdvertising {
                await storage.stop()
            }
        }
    }
    
    // MARK: - Methods
    
    public func start() async throws {
        try await start(options: AdvertisingOptions())
    }
    
    public func start(options: GATTPeripheralAdvertisingOptions) async throws {
        let isAdvertising = await self.isAdvertising
        assert(isAdvertising == false)
        
        // use public or random address
        let address: BluetoothAddress
        if let randomAddress = options.randomAddress {
            address = randomAddress
            try await hostController.lowEnergySetRandomAddress(randomAddress)
        } else {
            address = try await hostController.readDeviceAddress()
        }
        
        // set advertising data and scan response
        if options.advertisingData != nil || options.scanResponse != nil {
            do { try await hostController.enableLowEnergyAdvertising(false) }
            catch HCIError.commandDisallowed { /* ignore */ }
        }
        if let advertisingData = options.advertisingData {
            try await hostController.setLowEnergyAdvertisingData(advertisingData)
        }
        if let scanResponse = options.scanResponse {
            try await hostController.setLowEnergyScanResponse(scanResponse)
        }
        
        // enable advertising
        do { try await hostController.enableLowEnergyAdvertising() }
        catch HCIError.commandDisallowed { /* ignore */ }
        
        // create server socket
        let socket = try Socket.lowEnergyServer(
            address: address,
            isRandom: options.randomAddress != nil,
            backlog: self.options.socketBacklog
        )
        
        // start listening for connections
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            // wait for property to set
            while await self?.storage.task == nil {
                try? await Task.sleep(nanoseconds: 100_000)
            }
            self?.log?("Started GATT Server")
            // listen for
            while let self = self, await self.storage.isAdvertising, let socket = await self.storage.socket {
                await self.accept(socket)
            }
        }
        await self.storage.didStart(socket: socket, task: task)
    }
    
    public func stop() async {
        await storage.stop()
        log?("Stopped GATT Server")
    }
    
    public func add(service: BluetoothGATT.GATTAttribute<Data>.Service) async throws -> (UInt16, [UInt16]) {
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
    
    public func write(_ newValue: Data, forCharacteristic handle: UInt16, for central: Central) async throws {
        guard let connection = await storage.connections[central] else {
            throw CentralError.disconnected
        }
        await connection.write(newValue, forCharacteristic: handle)
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
                    await connection.write(newValue, forCharacteristic: handle)
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
    
    public subscript(characteristic handle: UInt16, central: Central) -> Data {
        get async throws {
            guard let connection = await storage.connections[central] else {
                throw CentralError.disconnected
            }
            return await connection[handle]
        }
    }
    
    /// Return the handles of the characteristics matching the specified UUID.
    public func characteristics(for uuid: BluetoothUUID) async -> [UInt16] {
        return await storage.database
            .lazy
            .filter { $0.uuid == uuid }
            .map { $0.handle }
    }
    
    private func log(_ central: Central, _ message: String) {
        log?("[\(central)]: " + message)
    }
}

extension GATTPeripheral {
    
    func callback(for central: Central) -> GATTServer<Socket.Connection>.Callback {
        var callback = GATTServer<Socket.Connection>.Callback()
        callback.willRead = { [weak self] in
            self?.willRead(central: central, uuid: $0, handle: $1, value: $2, offset: $3)
        }
        callback.willWrite = { [weak self] in
            self?.willWrite(central: central, uuid: $0, handle: $1, value: $2, newValue: $3)
        }
        callback.didWrite = { [weak self] (uuid, handle, value) in
            Task {
                await self?.didWrite(central: central, uuid: uuid, handle: handle, value: value)
            }
        }
        return callback
    }
    
    func updateMaximumUpdateValueLength(_ newValue: Int, for central: Central) {
        lock.lock()
        defer { lock.unlock() }
        self.maximumUpdateValueLength[central] = newValue
    }
    
    func maximumUpdateValueLength(for central: Central) -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard let maximumUpdateValueLength = self.maximumUpdateValueLength[central] else {
            assertionFailure()
            return Int(ATTMaximumTransmissionUnit.min.rawValue - 3)
        }
        return maximumUpdateValueLength
    }
    
    func willRead(central: Central, uuid: BluetoothUUID, handle: UInt16, value: Data, offset: Int) -> ATTError? {
        let maximumUpdateValueLength = maximumUpdateValueLength(for: central)
        let request = GATTReadRequest(
            central: central,
            maximumUpdateValueLength: maximumUpdateValueLength,
            uuid: uuid,
            handle: handle,
            value: value,
            offset: offset
        )
        return willRead?(request)
    }
    
    func willWrite(central: Central, uuid: BluetoothUUID, handle: UInt16, value: Data, newValue: Data) -> ATTError? {
        let maximumUpdateValueLength = maximumUpdateValueLength(for: central)
        let request = GATTWriteRequest(
            central: central,
            maximumUpdateValueLength: maximumUpdateValueLength,
            uuid: uuid,
            handle: handle,
            value: value,
            newValue: newValue
        )
        return willWrite?(request)
    }
    
    func didWrite(central: Central, uuid: BluetoothUUID, handle: UInt16, value: Data) async {
        let maximumUpdateValueLength = maximumUpdateValueLength(for: central)
        let confirmation = GATTWriteConfirmation(
            central: central,
            maximumUpdateValueLength: maximumUpdateValueLength,
            uuid: uuid,
            handle: handle,
            value: value
        )
        // update DB and inform other connections
        await write(confirmation.value, forCharacteristic: confirmation.handle, ignore: confirmation.central)
        // notify delegate
        await didWrite?(confirmation)
    }
    
    func accept(
        _ socket: Socket
    ) async {
        let log = self.log
        do {
            try Task.checkCancellation()
            // wait for pending socket
            while socket.status.accept == false, socket.status.error == nil {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            let newSocket = try socket.accept()
            log?("[\(newSocket.address)]: New connection")
            let central = Central(id: socket.address)
            let connection = GATTServerConnection(
                central: central,
                socket: newSocket,
                maximumTransmissionUnit: options.maximumTransmissionUnit,
                maximumPreparedWrites: options.maximumPreparedWrites,
                database: await storage.database,
                delegate: callback(for: central),
                log: {
                    log?("[\(central)]: " + $0)
                }
            )
            await storage.newConnection(connection)
            Task.detached { [weak connection, weak self] in
                do {
                    while let connection, let self {
                        try await Task.sleep(nanoseconds: 10_000)
                        // update cached MTU
                        let maximumUpdateValueLength = await connection.maximumUpdateValueLength
                        self.updateMaximumUpdateValueLength(maximumUpdateValueLength, for: central)
                        // read and write
                        try await connection.run()
                    }
                }
                catch {
                    log?("[\(central)]: " + error.localizedDescription)
                }
                await self?.didDisconnect(central, log: log)
            }
        }
        catch _ as CancellationError {
            return
        }
        catch {
            log?("Error waiting for new connection: \(error)")
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
    
    private nonisolated func didDisconnect(
        _ central: Central,
        log: (@Sendable (String) -> ())?
    ) async {
        // try advertising again
        let hostController = self.hostController
        do { try await hostController.enableLowEnergyAdvertising() }
        catch HCIError.commandDisallowed { /* ignore */ }
        catch { log?("Could not enable advertising. \(error)") }
        // remove connection cache
        await storage.removeConnection(central)
        // log
        log?("[\(central)]: " + "Did disconnect.")
    }
}

// MARK: - Supporting Types

public struct GATTPeripheralOptions: Equatable, Hashable, Sendable {
    
    public var maximumTransmissionUnit: ATTMaximumTransmissionUnit
    
    public var maximumPreparedWrites: Int
    
    public var socketBacklog: Int
    
    public init(
        maximumTransmissionUnit: ATTMaximumTransmissionUnit = .max,
        maximumPreparedWrites: Int = 100,
        socketBacklog: Int = 20
    ) {
        assert(maximumPreparedWrites > 0)
        assert(socketBacklog > 0)
        self.maximumTransmissionUnit = maximumTransmissionUnit
        self.maximumPreparedWrites = maximumPreparedWrites
        self.socketBacklog = socketBacklog
    }
}

public struct GATTPeripheralAdvertisingOptions: Equatable, Hashable, Sendable {
    
    public var advertisingData: LowEnergyAdvertisingData?
    
    public var scanResponse: LowEnergyAdvertisingData?
    
    public var randomAddress: BluetoothAddress?
    
    public init(
        advertisingData: LowEnergyAdvertisingData? = nil,
        scanResponse: LowEnergyAdvertisingData? = nil,
        randomAddress: BluetoothAddress? = nil
    ) {
        self.advertisingData = advertisingData
        self.scanResponse = scanResponse
        self.randomAddress = randomAddress
    }
}

internal extension GATTPeripheral {
    
    actor Storage {
        
        let hostController: HostController
        
        let options: Options
        
        var database = GATTDatabase<Data>()
        
        var socket: Socket?
        
        var task: Task<(), Never>?
        
        var connections = [Central: GATTServerConnection<Socket.Connection>](minimumCapacity: 2)
        
        fileprivate init(
            hostController: HostController,
            options: Options
        ) {
            self.hostController = hostController
            self.options = options
        }
        
        var isAdvertising: Bool {
            socket != nil
        }
        
        func stop() {
            assert(socket != nil)
            socket = nil
            task?.cancel()
            task = nil
        }
        
        func didStart(
            socket: Socket,
            task: Task<(), Never>?
        ) {
            self.socket = socket
            self.task = task
        }
        
        func add(service: GATTAttribute<Data>.Service) -> (UInt16, [UInt16]) {
            var includedServicesHandles = [UInt16]()
            var characteristicDeclarationHandles = [UInt16]()
            var characteristicValueHandles = [UInt16]()
            var descriptorHandles = [[UInt16]]()
            let serviceHandle = database.add(
                service: service,
                includedServicesHandles: &includedServicesHandles,
                characteristicDeclarationHandles: &characteristicDeclarationHandles,
                characteristicValueHandles: &characteristicValueHandles,
                descriptorHandles: &descriptorHandles
            )
            return (serviceHandle, characteristicValueHandles)
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
            _ connection: GATTServerConnection<Socket.Connection>
        ) {
            connections[connection.central] = connection
        }
        
        func removeConnection(_ central: Central) {
            self.connections[central] = nil
        }
        
        func maximumUpdateValueLength(for central: Central) async -> Int? {
            await connections[central]?.maximumUpdateValueLength
        }
    }
}

#endif
