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
    
    @available(*, deprecated, message: "Set value in `.init()`")
    public var newConnection: NewConnection?
    
    private lazy var queue = DispatchQueue(label: "\(type(of: self)) Queue")
    
    private lazy var concurrentQueue = DispatchQueue(label: "\(type(of: self)) Async Queue", qos: .userInitiated, attributes: [.concurrent])
    
    internal private(set) var scanData: [Peripheral: (ScanData<Peripheral, Advertisement>, HCILEAdvertisingReport.Report)] = [:]
    
    internal private(set) var connections = [Peripheral: GATTClientConnection<L2CAPSocket>](minimumCapacity: 1)
    
    private var lastConnectionID = 0
    
    // MARK: - Initialization
    
    public init(hostController: HostController,
                options: GATTCentralOptions = GATTCentralOptions(),
                newConnection: NewConnection? = nil) {
        
        self.hostController = hostController
        self.options = options
        self.newConnection = newConnection
    }
    
    // MARK: - Methods
    
    public func scan(filterDuplicates: Bool,
                     _ foundDevice: @escaping (Result<ScanData<Peripheral, Advertisement>, Error>) -> ()) {
        
        precondition(isScanning == false, "Already scanning")
        
        queue.async { [weak self] in
            guard let self = self else { return }
            self.log?("Scanning...")
            self.isScanning = true
            do {
                try hostController.lowEnergyScan(filterDuplicates: filterDuplicates, parameters: options.scanParameters, shouldContinue: { [unowned self] in self.isScanning }) { [unowned self] (report) in
                    
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
            assert(isScanning == false, "Invalid scanning state: \(isScanning)")
        }
    }
    
    public func stopScan() {
        
        self.log?("Stop scanning")
        self.isScanning = false
    }
    
    public func connect(to peripheral: Peripheral,
                        timeout: TimeInterval = .gattDefaultTimeout,
                        completion: @escaping (Result<Void, Error>) -> ()) {
        
        
        async(timeout: timeout, completion: completion) { (central) in
            guard let (scanData, report) = central.scanData[peripheral]
                else { throw CentralError.unknownPeripheral }
            // TODO: Remove in future version, make non-optional
            guard let newConnection = central.newConnection
                else { assertionFailure("Unable to create new connections"); return }
            // log
            self.log?("[\(scanData.peripheral)]: Open connection (\(report.addressType))")
            // open socket
            let socket = try newConnection(scanData, report)
            // configure connection object
            let callback = GATTClientConnectionCallback(
                log: central.log,
                didDisconnect: { [weak self] _ in
                    self?.disconnect(peripheral)
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
    }
    
    public func disconnect(_ peripheral: Peripheral) {
        
        queue.async { [weak self] in
            guard let self = self else { return }
            self.connections[peripheral] = nil
            self.didDisconnect?(peripheral)
        }
    }
    
    public func disconnectAll() {
        
        queue.async { [weak self] in
            guard let self = self else { return }
            let peripherals = self.didDisconnect != nil ? Array(self.connections.keys) : []
            self.connections.removeAll(keepingCapacity: true)
            if let didDisconnect = self.didDisconnect {
                peripherals.forEach { didDisconnect($0) }
            }
        }
    }
    
    public func discoverServices(_ services: [BluetoothUUID],
                                 for peripheral: Peripheral,
                                 timeout: TimeInterval,
                                 completion: @escaping (Result<[Service<Peripheral, AttributeID>], Error>) -> ())
        
        async(timeout: timeout, completion: completion) { (central) in
            try central.connection(for: peripheral)
                .discoverServices(services, for: peripheral, timeout: timeout)
        }
    }
    
    public func discoverCharacteristics(_ characteristics: [BluetoothUUID] = [],
                                        for service: Service<Peripheral, AttributeID>,
                                        timeout: TimeInterval = .gattDefaultTimeout) throws -> [Characteristic<Peripheral, AttributeID>] {
        
        return try connection(for: service.peripheral)
            .discoverCharacteristics(characteristics, for: service, timeout: timeout)
    }
    
    public func readValue(for characteristic: Characteristic<Peripheral, AttributeID>,
                          timeout: TimeInterval = .gattDefaultTimeout) throws -> Data {
        
        return try connection(for: characteristic.peripheral)
            .readValue(for: characteristic, timeout: timeout)
    }
    
    public func writeValue(_ data: Data,
                           for characteristic: Characteristic<Peripheral, AttributeID>,
                           withResponse: Bool = true,
                           timeout: TimeInterval = .gattDefaultTimeout) throws {
        
        return try connection(for: characteristic.peripheral)
            .writeValue(data, for: characteristic, withResponse: withResponse, timeout: timeout)
    }
    
    public func notify(_ notification: ((Data) -> ())?,
                       for characteristic: Characteristic<Peripheral, AttributeID>,
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
    
    private func async<T>(timeout: TimeInterval,
                          completion: @escaping (Result<T, Error>) -> (),
                          _ block: @escaping (GATTCentral) throws -> (T)) {
        
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
