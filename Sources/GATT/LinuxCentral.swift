//
//  LinuxCentral.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 1/22/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

#if os(Linux) || (Xcode && SWIFT_PACKAGE)
    
import Foundation
import Dispatch
import Bluetooth
import BluetoothLinux

@available(OSX 10.12, *)
public final class LinuxCentral: CentralProtocol {
    
    internal typealias AdvertisingReport = HCILEAdvertisingReport.Report
    
    public var log: ((String) -> ())?
    
    public let hostController: HostController
    
    internal lazy var asyncQueue = DispatchQueue(label: "\(type(of: self)) Operation Queue")
    
    internal private(set) var scanData = [Peripheral: AdvertisingReport](minimumCapacity: 1)
    
    internal private(set) var connections = [Peripheral: Server](minimumCapacity: 1)
    
    private var lastConnectionID = 0
    
    public init(hostController: HostController) {
        
        self.hostController = hostController
    }
    
    public func scan(filterDuplicates: Bool = true,
                     shouldContinueScanning: () -> (Bool),
                     foundDevice: @escaping (ScanData) -> ()) throws {
        
        self.log?("Scanning...")
        
        try hostController.lowEnergyScan(filterDuplicates: filterDuplicates, shouldContinue: shouldContinueScanning) { [unowned self] (report) in
            
            #if os(Linux)
            let peripheral = Peripheral(identifier: report.address)
            #elseif os(macOS)
            let peripheral = Peripheral(identifier: UUID())
            #endif
            
            let advertisement = AdvertisementData() // FIXME:
            
            let scanData = ScanData(date: Date(),
                                    peripheral: peripheral,
                                    rssi: Double(report.rssi.rawValue),
                                    advertisementData: advertisement)
            
            self.scanData[peripheral] = report
            
            foundDevice(scanData)
        }
    }
    
    public func connect(to peripheral: Peripheral, timeout: TimeInterval = 30) throws {
        
        guard let advertisementData = scanData[peripheral]
            else { throw CentralError.unknownPeripheral(peripheral) }
        
        let socket = try async(timeout: timeout) {
            
            try L2CAPSocket.lowEnergyClient(
                destination: (address: advertisementData.address,
                              type: AddressType(lowEnergy: advertisementData.addressType)
                )
            )
        }
        
        // keep connection open and store for future use
        self.connections[peripheral] = socket
    }
    
    public func disconnect(peripheral: Peripheral) {
        
        self.connections[peripheral] = nil
    }
    
    public func disconnectAll() {
        
        self.connections.removeAll(keepingCapacity: true)
    }
    
    public func discoverServices(_ services: [BluetoothUUID] = [],
                                 for peripheral: Peripheral,
                                 timeout: TimeInterval = 30) throws -> [Service] {
        
        guard let advertisementData = scanData[peripheral]
            else { throw CentralError.unknownPeripheral(peripheral) }
        
        guard let socket = connections[peripheral]
            else { throw CentralError.disconnected(peripheral) }
        
        
    }
    
    public func discoverCharacteristics(_ characteristics: [BluetoothUUID] = [],
                                        for service: BluetoothUUID,
                                        peripheral: Peripheral,
                                        timeout: TimeInterval = 30) throws -> [Characteristic] {
        
        
    }
    
    public func readValue(for characteristic: BluetoothUUID, service: BluetoothUUID, peripheral: Peripheral, timeout: TimeInterval = 30) throws -> Data {
        
        fatalError()
    }
    
    public func writeValue(_ data: Data, for characteristic: BluetoothUUID, withResponse: Bool = true, service: BluetoothUUID, peripheral: Peripheral, timeout: TimeInterval = 30) throws {
        
        fatalError()
    }
    
    public func notify(_ notification: ((Data) -> ())?, for characteristic: BluetoothUUID, service: BluetoothUUID, peripheral: Peripheral, timeout: TimeInterval = 30) throws {
        
        fatalError()
    }
    
    // MARK: - Private Methods
    
    fileprivate func newConnectionID() -> Int {
        
        lastConnectionID += 1
        
        return lastConnectionID
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

@available(OSX 10.12, *)
private extension LinuxCentral {
    
    final class Server {
        
        let connectionID: Int
        
        let peripheral: Peripheral
        
        let client: GATTClient
        
        
        
        lazy var thread: Thread = Thread { [weak self] in self?.main() }
    }
}

/// Basic wrapper for error / value pairs.
private enum ErrorValue<T> {
    
    case error(Error)
    case value(T)
}

#endif

#if os(Linux)
    
/// The platform specific peripheral.
public typealias CentralManager = LinuxCentral
    
#endif
