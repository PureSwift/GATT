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

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public actor GATTCentral <HostController: BluetoothHostControllerInterface, Socket: L2CAPSocket> : CentralManager {
    
    // MARK: - Properties
    
    public typealias Advertisement = LowEnergyAdvertisingData
    
    public typealias AttributeID = UInt16
    
    public typealias NewConnection = (ScanData<Peripheral, Advertisement>, HCILEAdvertisingReport.Report) throws -> (L2CAPSocket)
    
    public var log: ((String) -> ())?
    
    public let hostController: HostController
    
    public let options: GATTCentralOptions
    
    public private(set) var isScanning: Bool = false {
        didSet { scanningChanged?(isScanning) }
    }
    
    public var scanningChanged: ((Bool) -> ())?
    
    public var didDisconnect: ((Peripheral) -> ())?
    
    internal let newConnection: NewConnection
    
    internal let state: GATTCentralState
    
    // MARK: - Initialization
    
    public init(hostController: HostController,
                options: GATTCentralOptions = GATTCentralOptions(),
                newConnection: @escaping NewConnection) {
        
        self.hostController = hostController
        self.options = options
        self.newConnection = newConnection
    }
    
    // MARK: - Methods
    
    /// Scans for peripherals that are advertising services.
    public func scan(filterDuplicates: Bool) -> AsyncThrowingStream<ScanData<Peripheral, Advertisement>, Swift.Error> {
        precondition(isScanning == false, "Already scanning")
        self.log?("Scanning...")
        self.isScanning = true
        // FIXME: Use HCI async methods
        return AsyncThrowingStream(ScanData<Peripheral, Advertisement>.self, bufferingPolicy: .bufferingNewest(100)) { [weak self] continuation in
            guard let self = self else { return }
            /*
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.log?("Scanning...")
            self.isScanning = true
            do {
                try self.hostController.lowEnergyScan(filterDuplicates: filterDuplicates, parameters: self.options.scanParameters, shouldContinue: { [unowned self] in self.isScanning }) { [unowned self] (report) in
                    
                    let peripheral = Peripheral(identifier: report.address)
                    let isConnectable = report.event.isConnectable
                    let scanData = ScanData(
                        peripheral: peripheral,
                        date: Date(),
                        rssi: Double(report.rssi?.rawValue ?? 0),
                        advertisementData: report.responseData,
                        isConnectable: isConnectable
                    )
                    self.scanData[peripheral] = (scanData, report)
                    foundDevice(.success(scanData))
                }
            } catch {
                self.isScanning = false
                self.log?("Unable to scan: \(error)")
            }
            
            self.log?("Did discover \(self.scanData.count) peripherals")
            assert(self.isScanning == false, "Invalid scanning state: \(self.isScanning)")
             */
        }
    }
    
    public func stopScan() async {
        self.log?("Stop scanning")
        self.isScanning = false
    }
    
    public func connect(to peripheral: Peripheral) async throws {
        // get scan data (bluetooth address) for new connection
        guard let (scanData, report) = self.state.scanData[peripheral]
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
        let connection = GATTClientConnection(
            peripheral: peripheral,
            socket: socket,
            maximumTransmissionUnit: self.options.maximumTransmissionUnit,
            callback: callback
        )
        // store connection
        self.connections[peripheral] = connection
    }
    
    public func disconnect(_ peripheral: Peripheral) async {
        self.connections[peripheral] = nil
        self.didDisconnect?(peripheral)
    }
    
    public func disconnectAll() async {
        let peripherals = self.didDisconnect != nil ? Array(self.connections.keys) : []
        self.connections.removeAll(keepingCapacity: true)
        if let didDisconnect = self.didDisconnect {
            peripherals.forEach { didDisconnect($0) }
        }
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
        return AsyncThrowingStream(Data.self, bufferingPolicy: .bufferingNewest(1000)) {
            try await connection(for: characteristic.peripheral)
                .notify(for: characteristic)
        }
    }
    
    // Stop Notifications
    public func stopNotifications(for characteristic: Characteristic<Peripheral, UInt16>) async throws {
        try await connection(for: characteristic.peripheral)
            
    }
    
    /// Read MTU
    public func maximumTransmissionUnit(for peripheral: Peripheral) async throws -> MaximumTransmissionUnit {
        return try await connection(for: peripheral).client.maximumTransmissionUnit
    }
    
    // Read RSSI
    public func rssi(for peripheral: Peripheral) async throws -> RSSI {
        
    }
    
    // MARK: - Private Methods
    
    private func newConnectionID() -> Int {
        lastConnectionID += 1
        return lastConnectionID
    }
    
    private func connection(for peripheral: Peripheral) throws -> GATTClientConnection<L2CAPSocket> {
        
        guard let _ = scanData[peripheral]
            else { throw CentralError.unknownPeripheral }
        guard let connection = connections[peripheral]
            else { throw CentralError.disconnected }
        return connection
    }
    
    private func async<T>(timeout: TimeInterval,
                          completion: @escaping (Result<T, Error>) -> (),
                          _ block: @escaping (Self) throws -> (T)) {
        
        queue.async { [weak self] in
            let semaphore = Semaphore<T>(timeout: timeout)
            self?.concurrentQueue.async { [weak self] in
                guard let self = self else { return }
                do {
                    let value = try block(self)
                    semaphore.stopWaiting(.success(value))
                }
                catch { semaphore.stopWaiting(.failure(error)) }
            }
            let result = Result<T, Error>(catching: { try semaphore.wait() })
            completion(result)
        }
    }
}

// MARK: - Supporting Types

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
internal actor GATTCentralState {
    
    fileprivate(set) var scanData = [Peripheral: (ScanData<Peripheral, Advertisement>, HCILEAdvertisingReport.Report)]()
    
    fileprivate(set) var connections = [Peripheral: GATTClientConnection<L2CAPSocket>](minimumCapacity: 1)
    
    fileprivate var lastConnectionID = 0
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
