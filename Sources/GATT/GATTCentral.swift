//
//  GATTCentral.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 7/18/18.
//

#if canImport(Foundation)
import Foundation
#endif
#if canImport(BluetoothGATT) && canImport(BluetoothHCI)
@_exported import Bluetooth
@_exported import BluetoothGATT
@_exported import BluetoothHCI

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public final class GATTCentral <HostController: BluetoothHostControllerInterface, Socket: L2CAPConnection>: CentralManager, @unchecked Sendable where Socket: Sendable {
    
    public typealias Peripheral = GATT.Peripheral
    
    public typealias Data = Socket.Data
    
    public typealias Options = GATTCentralOptions
    
    // MARK: - Properties
    
    public typealias Advertisement = LowEnergyAdvertisingData
    
    public typealias AttributeID = UInt16
    
    public var log: (@Sendable (String) -> ())?
    
    public let hostController: HostController
    
    public let options: Options
    
    /// Currently scanned devices, or restored devices.
    public var peripherals: [Peripheral: Bool] {
        get async {
            await storage.peripherals
        }
    }
    
    internal let storage = Storage()
    
    // MARK: - Initialization
    
    public init(
        hostController: HostController,
        options: Options = Options(),
        socket: Socket.Type
    ) {
        self.hostController = hostController
        self.options = options
    }
    
    // MARK: - Methods
    
    /// Scans for peripherals that are advertising services.
    public func scan(
        filterDuplicates: Bool
    ) async throws -> AsyncCentralScan<GATTCentral> {
        let scanParameters = HCILESetScanParameters(
            type: .active,
            interval: LowEnergyScanTimeInterval(rawValue: 0x01E0)!,
            window: LowEnergyScanTimeInterval(rawValue: 0x0030)!,
            addressType: .public,
            filterPolicy: .accept
        )
        return try await scan(filterDuplicates: filterDuplicates, parameters: scanParameters)
    }
    
    /// Scans for peripherals that are advertising services.
    public func scan(
        filterDuplicates: Bool,
        parameters: HCILESetScanParameters
    ) async throws -> AsyncCentralScan<GATTCentral> {
        self.log?("Scanning...")
        let stream = try await self.hostController.lowEnergyScan(
            filterDuplicates: filterDuplicates,
            parameters: parameters
        )
        return AsyncCentralScan { [unowned self] continuation in
            // start scanning
            for try await report in stream {
                let scanData = await self.storage.found(report)
                continuation(scanData)
            }
        }
    }
    
    public func connect(to peripheral: Peripheral) async throws {
        // get scan data (Bluetooth address) for new connection
        guard let (scanData, report) = await self.storage.scanData[peripheral]
            else { throw CentralError.unknownPeripheral }
        // log
        self.log(scanData.peripheral, "Open connection (\(report.addressType))")
        // load cache device address
        let localAddress = try await storage.readAddress(hostController)
        // open socket
        let socket = try Socket.lowEnergyClient(
            address: localAddress,
            destination: report
        )
        let connection = await GATTClientConnection(
            peripheral: peripheral,
            socket: socket,
            maximumTransmissionUnit: self.options.maximumTransmissionUnit,
            log: { [weak self] in
                self?.log(peripheral, $0)
            }
        )
        // store connection
        await self.storage.didConnect(connection, socket)
        Task.detached { [weak self, weak connection] in
            do {
                while let connection {
                    try await Task.sleep(nanoseconds: 10_000)
                    try await connection.run()
                }
            }
            catch {
                self?.log(peripheral, error.localizedDescription)
            }
            await self?.storage.removeConnection(peripheral)
        }
    }
    
    public func disconnect(_ peripheral: Peripheral) async {
        if let (_, socket) = await storage.connections[peripheral] {
            socket.close()
        }
        await storage.removeConnection(peripheral)
    }
    
    public func disconnectAll() async {
        for (_, socket) in await storage.connections.values {
            socket.close()
        }
        await storage.removeAllConnections()
    }
    
    public func discoverServices(
        _ services: Set<BluetoothUUID> = [],
        for peripheral: Peripheral
    ) async throws -> [Service<Peripheral, UInt16>] {
        return try await connection(for: peripheral)
            .discoverServices(services)
    }
    
    /// Discover Characteristics for service
    public func discoverCharacteristics(
        _ characteristics: Set<BluetoothUUID> = [],
        for service: Service<Peripheral, UInt16>
    ) async throws -> [Characteristic<Peripheral, UInt16>] {
        return try await connection(for: service.peripheral)
            .discoverCharacteristics(characteristics, for: service)
    }
    
    /// Read Characteristic Value
    public func readValue(
        for characteristic: Characteristic<Peripheral, UInt16>
    ) async throws -> Data {
        return try await connection(for: characteristic.peripheral)
            .readValue(for: characteristic)
    }
    
    /// Write Characteristic Value
    public func writeValue(
        _ data: Data,
        for characteristic: Characteristic<Peripheral, UInt16>,
        withResponse: Bool = true
    ) async throws {
        try await connection(for: characteristic.peripheral)
            .writeValue(data, for: characteristic, withResponse: withResponse)
    }
    
    /// Start Notifications
    public func notify(
        for characteristic: Characteristic<Peripheral, UInt16>
    ) -> AsyncCentralNotifications<GATTCentral> {
        return AsyncCentralNotifications(onTermination: {
            Task(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                do {
                    // start notifications
                    try await self.connection(for: characteristic.peripheral)
                        .notify(characteristic, notification: .none)
                }
                catch {
                    self.log?("Unable to stop notifications for \(characteristic.uuid)")
                }
            }
        }) { continuation in
            Task(priority: .userInitiated) {
                do {
                    // start notifications
                    try await connection(for: characteristic.peripheral)
                        .notify(characteristic) { continuation.yield($0) }
                }
                catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    public func discoverDescriptors(for characteristic: Characteristic<Peripheral, UInt16>) async throws -> [Descriptor<Peripheral, UInt16>] {
        try await connection(for: characteristic.peripheral)
            .discoverDescriptors(for: characteristic)
    }
    
    public func readValue(for descriptor: Descriptor<Peripheral, UInt16>) async throws -> Data {
        try await connection(for: descriptor.peripheral)
            .readValue(for: descriptor)
    }
    
    public func writeValue(_ data: Data, for descriptor: Descriptor<Peripheral, UInt16>) async throws {
        try await connection(for: descriptor.peripheral)
            .writeValue(data, for: descriptor)
    }
    
    /// Read MTU
    public func maximumTransmissionUnit(for peripheral: Peripheral) async throws -> MaximumTransmissionUnit {
        return try await connection(for: peripheral)
            .client.maximumTransmissionUnit
    }
    
    // Read RSSI
    public func rssi(for peripheral: Peripheral) async throws -> RSSI {
        RSSI(rawValue: +20)!
    }
    
    // MARK: - Private Methods
    
    private func connection(for peripheral: Peripheral) async throws -> GATTClientConnection<Socket> {
        
        guard await storage.scanData.keys.contains(peripheral)
            else { throw CentralError.unknownPeripheral }
        
        guard let (connection, _) = await storage.connections[peripheral]
            else { throw CentralError.disconnected }
        
        return connection
    }
    
    private func log(_ peripheral: Peripheral, _ message: String) {
        log?("[\(peripheral)]: " + message)
    }
}

// MARK: - Supporting Types

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
internal extension GATTCentral {
    
    actor Storage {
        
        var address: BluetoothAddress?
        
        var scanData = [Peripheral: (ScanData<Peripheral, Advertisement>, HCILEAdvertisingReport.Report)]()
        
        var connections = [Peripheral: (connection: GATTClientConnection<Socket>, socket: Socket)](minimumCapacity: 2)
        
        var peripherals: [Peripheral: Bool] {
            get async {
                let peripherals = scanData.keys
                let connections = connections.keys
                var result = [Peripheral: Bool]()
                result.reserveCapacity(peripherals.count)
                return peripherals.reduce(into: result, { $0[$1] = connections.contains($1) })
            }
        }
        
        func found(_ report: HCILEAdvertisingReport.Report) -> ScanData<Peripheral, Advertisement> {
            let peripheral = Peripheral(id: report.address)
            let scanData = ScanData(
                peripheral: peripheral,
                date: Date(),
                rssi: Double(report.rssi?.rawValue ?? 0),
                advertisementData: report.responseData,
                isConnectable: report.event.isConnectable
            )
            self.scanData[peripheral] = (scanData, report)
            return scanData
        }
        
        func readAddress(_ hostController: HostController) async throws -> BluetoothAddress {
            if let cachedAddress = self.address {
                return cachedAddress
            } else {
                let address = try await hostController.readDeviceAddress()
                self.address = address
                return address
            }
        }
        
        func didConnect(_ connection: GATTClientConnection<Socket>, _ socket: Socket) {
            self.connections[connection.peripheral] = (connection, socket)
        }
        
        func removeConnection(_ peripheral: Peripheral) async {
            self.connections[peripheral] = nil
        }
        
        func removeAllConnections() async {
            self.connections.removeAll(keepingCapacity: true)
        }
    }
}

public struct GATTCentralOptions {
    
    public let maximumTransmissionUnit: ATTMaximumTransmissionUnit
        
    public init(maximumTransmissionUnit: ATTMaximumTransmissionUnit = .default) {
        self.maximumTransmissionUnit = maximumTransmissionUnit
    }
}

#endif
