//
//  GATTCentral.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 7/18/18.
//

#if swift(>=5.6) && canImport(BluetoothGATT) && canImport(BluetoothHCI)
import Foundation
@_exported import Bluetooth
@_exported import BluetoothGATT
@_exported import BluetoothHCI

@available(macOS 10.5, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public final class GATTCentral <HostController: BluetoothHostControllerInterface, Socket: L2CAPSocket>: CentralManager {
    
    public typealias Options = GATTCentralOptions
    
    // MARK: - Properties
    
    public typealias Advertisement = LowEnergyAdvertisingData
    
    public typealias AttributeID = UInt16
        
    public var log: ((String) -> ())?
    
    public let hostController: HostController
    
    public let options: Options
    
    /// Currently scanned devices, or restored devices.
    public var peripherals: Set<Peripheral> {
        get async {
            return await Set(storage.scanData.keys)
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
        // get scan data (bluetooth address) for new connection
        guard let (scanData, report) = await self.storage.scanData[peripheral]
            else { throw CentralError.unknownPeripheral }
        // log
        self.log?("[\(scanData.peripheral)]: Open connection (\(report.addressType))")
        // load cache device address
        let localAddress = try await storage.readAddress(hostController)
        // open socket
        let socket = try await Socket.lowEnergyClient(
            address: localAddress,
            destination: report
        )
        // keep connection open and store for future use
        let connection = await GATTClientConnection(
            peripheral: peripheral,
            socket: socket,
            maximumTransmissionUnit: self.options.maximumTransmissionUnit,
            delegate: self
        )
        // store connection
        await self.storage.didConnect(connection)
    }
    
    public func disconnect(_ peripheral: Peripheral) async {
        await storage.removeConnection(peripheral)
    }
    
    public func disconnectAll() async {
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
        fatalError()
    }
    
    public func readValue(for descriptor: Descriptor<Peripheral, UInt16>) async throws -> Data {
        fatalError()
    }
    
    public func writeValue(_ data: Data, for descriptor: Descriptor<Peripheral, UInt16>) async throws {
        fatalError()
    }
    
    /// Read MTU
    public func maximumTransmissionUnit(for peripheral: Peripheral) async throws -> MaximumTransmissionUnit {
        return try await connection(for: peripheral).client.maximumTransmissionUnit
    }
    
    // Read RSSI
    public func rssi(for peripheral: Peripheral) async throws -> RSSI {
        RSSI(rawValue: +20)!
    }
    
    // MARK: - Private Methods
    
    private func connection(for peripheral: Peripheral) async throws -> GATTClientConnection<Socket> {
        
        guard await storage.scanData.keys.contains(peripheral)
            else { throw CentralError.unknownPeripheral }
        
        guard let connection = await storage.connections[peripheral]
            else { throw CentralError.disconnected }
        
        return connection
    }
}

extension GATTCentral: GATTClientConnectionDelegate {
    
    func connection(_ peripheral: Peripheral, log message: String) {
        log?("[\(peripheral)]: " + message)
    }
    
    func connection(_ peripheral: Peripheral, didDisconnect error: Swift.Error?) async {
        await storage.removeConnection(peripheral)
        log?("[\(peripheral)]: " + "did disconnect \(error?.localizedDescription ?? "")")
    }
}

// MARK: - Supporting Types

@available(macOS 10.5, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
internal extension GATTCentral {
    
    actor Storage {
        
        var scanData = [Peripheral: (ScanData<Peripheral, Advertisement>, HCILEAdvertisingReport.Report)]()
        
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
        
        var address: BluetoothAddress?
        
        func readAddress(_ hostController: HostController) async throws -> BluetoothAddress {
            if let cachedAddress = self.address {
                return cachedAddress
            } else {
                let address = try await hostController.readDeviceAddress()
                self.address = address
                return address
            }
        }
        
        var connections = [Peripheral: GATTClientConnection<Socket>](minimumCapacity: 2)
        
        func didConnect(_ connection: GATTClientConnection<Socket>) {
            self.connections[connection.peripheral] = connection
        }
        
        func removeConnection(_ peripheral: Peripheral) {
            self.connections[peripheral] = nil
        }
        
        func removeAllConnections() {
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
