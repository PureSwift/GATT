//
//  GATTCentral.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 7/18/18.
//


import Foundation
import Dispatch
import Bluetooth

@available(OSX 10.12, iOS 10.0, watchOS 3.0, tvOS 10.0, *)
public final class GATTCentral <HostController: BluetoothHostControllerInterface, L2CAPSocket: L2CAPSocketProtocol>: CentralProtocol {
    
    public typealias Advertisement = AdvertisementData
    
    public typealias AdvertisingReport = HCILEAdvertisingReport.Report
    
    public var log: ((String) -> ())?
    
    public let hostController: HostController
    
    public let maximumTransmissionUnit: ATTMaximumTransmissionUnit
    
    public var newConnection: ((AdvertisingReport) throws -> (L2CAPSocket))?
    
    internal lazy var asyncQueue: DispatchQueue = DispatchQueue(label: "\(type(of: self)) Operation Queue")
    
    internal private(set) var scanData = [Peripheral: (report: AdvertisingReport, scanData: ScanData<Peripheral, AdvertisementData>)](minimumCapacity: 1)
    
    internal private(set) var connections = [Peripheral: GATTClientConnection<L2CAPSocket>](minimumCapacity: 1)
    
    private var lastConnectionID = 0
    
    public init(hostController: HostController,
                maximumTransmissionUnit: ATTMaximumTransmissionUnit = .default) {
        
        self.hostController = hostController
        self.maximumTransmissionUnit = maximumTransmissionUnit
    }
    
    public func scan(filterDuplicates: Bool = true,
                     shouldContinueScanning: () -> (Bool),
                     foundDevice: @escaping (ScanData<Peripheral, AdvertisementData>) -> ()) throws {
        
        self.log?("Scanning...")
        
        try hostController.lowEnergyScan(filterDuplicates: filterDuplicates, shouldContinue: shouldContinueScanning) { [unowned self] (report) in
            
            let peripheral = Peripheral(identifier: report.address)
            
            let advertisement = Advertisement(data: report.responseData)
            
            let scanData = ScanData(peripheral: peripheral,
                                    date: Date(),
                                    rssi: Double(report.rssi.rawValue),
                                    advertisementData: advertisement)
            
            self.scanData[peripheral] = (report, scanData)
            
            foundDevice(scanData)
        }
        
        self.log?("Did discover \(self.scanData.count) peripherals")
    }
    
    public func connect(to peripheral: Peripheral, timeout: TimeInterval = .gattDefaultTimeout) throws {
        
        guard let report = scanData[peripheral]?.report
            else { throw CentralError.unknownPeripheral }
        
        guard let newConnection = self.newConnection
            else { return }
        
        let socket = try async(timeout: timeout) { try newConnection(report) }
        
        /**
        try L2CAPSocket.lowEnergyClient(
            destination: (address: advertisementData.address,
                          type: AddressType(lowEnergy: advertisementData.addressType)
            )
        )
         */
        
        // keep connection open and store for future use
        let connection = GATTClientConnection(peripheral: peripheral,
                                              socket: socket,
                                              maximumTransmissionUnit: maximumTransmissionUnit)
        
        connection.callback.log = { [weak self] in self?.log?($0) }
        
        connection.callback.didDisconnect = { [weak self] _ in
            self?.disconnect(peripheral: peripheral)
        }
        
        // store connection
        self.connections[peripheral] = connection
    }
    
    public func disconnect(peripheral: Peripheral) {
        
        self.connections[peripheral] = nil
    }
    
    public func disconnectAll() {
        
        self.connections.removeAll(keepingCapacity: true)
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
    
    public func maximumTransmissionUnit(for peripheral: Peripheral) throws -> ATTMaximumTransmissionUnit {
        
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

/// Basic wrapper for error / value pairs.
private enum ErrorValue<T> {
    
    case error(Error)
    case value(T)
}
