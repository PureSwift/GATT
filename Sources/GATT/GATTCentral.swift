//
//  GATTCentral.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 7/18/18.
//

#if swift(>=5.5) && canImport(BluetoothGATT) && canImport(BluetoothHCI)
import Foundation
@_exported import Bluetooth
@_exported import BluetoothGATT
@_exported import BluetoothHCI

@available(macOS 10.5, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public final class GATTCentral <HostController: BluetoothHostControllerInterface, Socket: L2CAPSocket> /* : CentralManager */ {
    
    // MARK: - Properties
    
    public typealias Advertisement = LowEnergyAdvertisingData
    
    public typealias AttributeID = UInt16
    
    public typealias NewConnection = (ScanData<Peripheral, Advertisement>, HCILEAdvertisingReport.Report) throws -> (Socket)
    
    public let log: ((String) -> ())?
    
    public let hostController: HostController
    
    public let options: GATTCentralOptions
    
    internal let newConnection: NewConnection
    
    internal let state = GATTCentralState()
    
    // MARK: - Initialization
    
    public init(
        hostController: HostController,
        options: GATTCentralOptions = GATTCentralOptions(),
        newConnection: @escaping NewConnection,
        log: ((String) -> ())? = nil
    ) {
        self.hostController = hostController
        self.options = options
        self.newConnection = newConnection
        self.log = log
    }
    
    // MARK: - Methods
    
    /// Scans for peripherals that are advertising services.
    public func scan(
        filterDuplicates: Bool
    ) -> AsyncThrowingStream<ScanData<Peripheral, Advertisement>, Swift.Error> {
        return AsyncThrowingStream(ScanData<Peripheral, Advertisement>.self, bufferingPolicy: .bufferingNewest(30)) { continuation in
            Task(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                // wait until scanning is possible
                while await self.state.scanningStream != nil {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                }
                // start scanning
                self.log?("Scanning...")
                let stream = self.hostController.lowEnergyScan(
                    filterDuplicates: filterDuplicates,
                    parameters: self.options.scanParameters
                )
                // store stream
                await self.state.startScanning(stream)
                // store
                do {
                    for try await report in stream {
                        let scanData = await self.state.found(report)
                        continuation.yield(scanData)
                    }
                    continuation.finish()
                }
                catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    public func stopScan() async {
        self.log?("Stop scanning")
        await self.state.stopScanning()
    }
    
    public func connect(to peripheral: Peripheral) async throws {
        // get scan data (bluetooth address) for new connection
        guard let (scanData, report) = await self.state.scanData[peripheral]
            else { throw CentralError.unknownPeripheral }
        // log
        self.log?("[\(scanData.peripheral)]: Open connection (\(report.addressType))")
        // open socket
        let socket = try self.newConnection(scanData, report)
        // configure connection object
        let callback = GATTClientConnectionCallback(
            log: self.log,
            didDisconnect: { [weak self] _ in
                //self?.disconnect(peripheral)
            }
        )
        // keep connection open and store for future use
        let connection = await GATTClientConnection<Socket>(
            peripheral: peripheral,
            socket: socket,
            maximumTransmissionUnit: self.options.maximumTransmissionUnit,
            callback: callback
        )
        // store connection
        await self.state.didConnect(connection)
    }
    
    public func disconnect(_ peripheral: Peripheral) async {
        await state.removeConnection(peripheral)
        // TODO: Emit notification
        //self.didDisconnect?(peripheral)
    }
    
    public func disconnectAll() async {
        await state.removeAllConnections()
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
    ) async -> AsyncThrowingStream<Data, Swift.Error> {
        return AsyncThrowingStream(Data.self, bufferingPolicy: .bufferingNewest(1000)) { continuation in
            Task(priority: .userInitiated) {
                do {
                    let stream = try await connection(for: characteristic.peripheral)
                        .notify(for: characteristic)
                    for try await notification in stream {
                        continuation.yield(notification)
                    }
                    continuation.finish()
                }
                catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    // Stop Notifications
    public func stopNotifications(for characteristic: Characteristic<Peripheral, UInt16>) async throws {
        try await connection(for: characteristic.peripheral)
            .notify(characteristic, notification: nil)
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
        
        guard await state.scanData.keys.contains(peripheral)
            else { throw CentralError.unknownPeripheral }
        
        guard let connection = await state.connections[peripheral]
            else { throw CentralError.disconnected }
        
        return connection
    }
}

// MARK: - Supporting Types

@available(macOS 10.5, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
internal extension GATTCentral {
    
    actor GATTCentralState {
        
        var scanningStream: AsyncLowEnergyScanStream?
        
        func startScanning(_ stream: AsyncLowEnergyScanStream) {
            self.scanningStream = stream
        }
        
        func stopScanning() {
            self.scanningStream?.stop()
        }
        
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
        
        var lastConnectionID: UInt = 0
        
        func newConnectionID() -> UInt {
            lastConnectionID += 1
            return lastConnectionID
        }
    }
}

public struct GATTCentralOptions {
    
    public let maximumTransmissionUnit: ATTMaximumTransmissionUnit
    
    public let scanParameters: HCILESetScanParameters
    
    public init(maximumTransmissionUnit: ATTMaximumTransmissionUnit = .max,
                scanParameters: HCILESetScanParameters = .gattCentralDefault) {
        
        self.maximumTransmissionUnit = maximumTransmissionUnit
        self.scanParameters = scanParameters
    }
}

public extension HCILESetScanParameters {
    
    static var gattCentralDefault: HCILESetScanParameters {
        
        return HCILESetScanParameters(
            type: .active,
            interval: LowEnergyScanTimeInterval(rawValue: 0x01E0)!,
            window: LowEnergyScanTimeInterval(rawValue: 0x0030)!,
            addressType: .public,
            filterPolicy: .accept
        )
    }
}

#endif
