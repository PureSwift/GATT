//
//  GATTCentral.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 7/18/18.
//

#if canImport(BluetoothGATT) && canImport(BluetoothHCI)
import Foundation
import Dispatch
@_exported import Bluetooth
@_exported import BluetoothGATT
@_exported import BluetoothHCI

@available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)
public final class GATTCentral <HostController: BluetoothHostControllerInterface, L2CAPSocket: L2CAPSocketProtocol>: CentralProtocol {
    
    // MARK: - Properties
    
    public typealias Advertisement = LowEnergyAdvertisingData
    
    public var log: ((String) -> ())?
    
    public let hostController: HostController
    
    public let options: GATTCentralOptions
    
    public private(set) var isScanning: Bool = false
    
    public var didDisconnect: ((Peripheral) -> ())?
    
    public var newConnection: ((ScanData<Peripheral, Advertisement>, HCILEAdvertisingReport.Report) throws -> (L2CAPSocket))?
    
    internal lazy var asyncQueue: DispatchQueue = DispatchQueue(label: "\(type(of: self)) Operation Queue")
    
    internal private(set) var scanData: [Peripheral: (ScanData<Peripheral, Advertisement>, HCILEAdvertisingReport.Report)] = [:]
    
    internal private(set) var connections = [Peripheral: GATTClientConnection<L2CAPSocket>](minimumCapacity: 1)
    
    private var lastConnectionID = 0
    
    // MARK: - Initialization
    
    public init(hostController: HostController,
                options: GATTCentralOptions = GATTCentralOptions()) {
        
        self.hostController = hostController
        self.options = options
    }
    
    // MARK: - Methods
    
    public func scan(filterDuplicates: Bool = true,
                     foundDevice: @escaping (ScanData<Peripheral, Advertisement>) -> ()) throws {
                
        self.log?("Scanning...")
        
        self.isScanning = true
        
        do {
            
            try hostController.lowEnergyScan(filterDuplicates: filterDuplicates, parameters: options.scanParameters, shouldContinue: { [unowned self] in self.isScanning }) { [unowned self] (report) in
                
                let peripheral = Peripheral(identifier: report.address)
                
                let isConnectable = report.event.isConnectable
                
                let scanData = ScanData(peripheral: peripheral,
                                        date: Date(),
                                        rssi: Double(report.rssi?.rawValue ?? 0),
                                        advertisementData: report.responseData,
                                        isConnectable: isConnectable)
                
                self.scanData[peripheral] = (scanData, report)
                
                foundDevice(scanData)
            }
        } catch {
            self.isScanning = false
            throw error
        }
        
        self.log?("Did discover \(self.scanData.count) peripherals")
        assert(isScanning == false, "Invalid scanning state: \(isScanning)")
    }
    
    public func stopScan() {
        
        self.log?("Stop scanning")
        self.isScanning = false
    }
    
    public func connect(to peripheral: Peripheral, timeout: TimeInterval = .gattDefaultTimeout) throws {
        
        guard let (scanData, report) = scanData[peripheral]
            else { throw CentralError.unknownPeripheral }
        
        guard let newConnection = self.newConnection
            else { return }
        
        // log
        self.log?("[\(scanData.peripheral)]: Open connection (\(report.addressType))")
        
        // open socket
        let socket = try async(timeout: timeout) { try newConnection(scanData, report) }
        
        // configure connection object
        let callback = GATTClientConnectionCallback(
            log: self.log,
            didDisconnect: { [weak self] _ in
                self?.disconnect(peripheral: peripheral)
            }
        )
        
        // keep connection open and store for future use
        let connection = GATTClientConnection(peripheral: peripheral,
                                              socket: socket,
                                              maximumTransmissionUnit: options.maximumTransmissionUnit,
                                              callback: callback)
        
        // store connection
        self.connections[peripheral] = connection
    }
    
    public func disconnect(peripheral: Peripheral) {
        
        self.connections[peripheral] = nil
        
        // L2CAP socket may be retained by background thread
        sleep(1)
        
        didDisconnect?(peripheral)
    }
    
    public func disconnectAll() {
        
        let peripherals = self.didDisconnect != nil ? Array(self.connections.keys) : []
        
        self.connections.removeAll(keepingCapacity: true)
        
        sleep(1)
        
        if let didDisconnect = self.didDisconnect {
            peripherals.forEach { didDisconnect($0) }
        }
    }
    
    public func discoverServices(_ services: [BluetoothUUID] = [],
                                 for peripheral: Peripheral,
                                 timeout: TimeInterval = .gattDefaultTimeout) throws -> [Service<Peripheral>] {
        
        return try connection(for: peripheral)
            .discoverServices(services, for: peripheral, timeout: timeout)
    }
    
    public func discoverCharacteristics(_ characteristics: [BluetoothUUID] = [],
                                        for service: Service<Peripheral>,
                                        timeout: TimeInterval = .gattDefaultTimeout) throws -> [Characteristic<Peripheral>] {
        
        return try connection(for: service.peripheral)
            .discoverCharacteristics(characteristics, for: service, timeout: timeout)
    }
    
    public func readValue(for characteristic: Characteristic<Peripheral>,
                          timeout: TimeInterval = .gattDefaultTimeout) throws -> Data {
        
        return try connection(for: characteristic.peripheral)
            .readValue(for: characteristic, timeout: timeout)
    }
    
    public func writeValue(_ data: Data,
                           for characteristic: Characteristic<Peripheral>,
                           withResponse: Bool = true,
                           timeout: TimeInterval = .gattDefaultTimeout) throws {
        
        return try connection(for: characteristic.peripheral)
            .writeValue(data, for: characteristic, withResponse: withResponse, timeout: timeout)
    }
    
    public func notify(_ notification: ((Data) -> ())?,
                       for characteristic: Characteristic<Peripheral>,
                       timeout: TimeInterval = .gattDefaultTimeout) throws {
        
        return try connection(for: characteristic.peripheral)
            .notify(notification, for: characteristic, timeout: timeout)
    }
    
    public func maximumTransmissionUnit(for peripheral: Peripheral) throws -> MaximumTransmissionUnit {
        return try connection(for: peripheral).client.maximumTransmissionUnit
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
    
    private func async <T> (timeout: TimeInterval, _ operation: @escaping () throws -> (T)) throws -> (T) {
        
        var result: ErrorValue<T>?
        
        asyncQueue.async {
            
            do { result = .value(try operation()) }
                
            catch { result = .error(error) }
        }
        
        let endDate = Date() + timeout
        
        while Date() < endDate {
            
            guard let response = result
                else { usleep(100); continue }
            
            switch response {
            case let .error(error):
                throw error
            case let .value(value):
                return value
            }
        }
        
        // did timeout
        throw CentralError.timeout
    }
}

// MARK: - Supporting Types

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

/// Basic wrapper for error / value pairs.
private enum ErrorValue<T> {
    
    case error(Error)
    case value(T)
}

#endif
