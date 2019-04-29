//
//  Central.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/3/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import Foundation
import Bluetooth

/// GATT Central Manager
///
/// Implementation varies by operating system.
public protocol CentralProtocol: class {
    
    associatedtype Peripheral: Peer
    
    associatedtype Advertisement: AdvertisementDataProtocol
    
    var log: ((String) -> ())? { get set }
    
    /// Scans for peripherals that are advertising services.
    func scan(filterDuplicates: Bool,
              foundDevice: @escaping (ScanData<Peripheral, Advertisement>) -> ()) throws
    
    /// Stops scanning for peripherals.
    func stopScan()
    
    var isScanning: Bool { get }
    
    func connect(to peripheral: Peripheral, timeout: TimeInterval) throws
    
    func disconnect(peripheral: Peripheral)
    
    func disconnectAll()
    
    func discoverServices(_ services: [BluetoothUUID],
                          for peripheral: Peripheral,
                          timeout: TimeInterval) throws -> [Service<Peripheral>]
    
    func discoverCharacteristics(_ characteristics: [BluetoothUUID],
                                for service: Service<Peripheral>,
                                timeout: TimeInterval) throws -> [Characteristic<Peripheral>]
    
    func readValue(for characteristic: Characteristic<Peripheral>,
                   timeout: TimeInterval) throws -> Data
    
    func writeValue(_ data: Data,
                    for characteristic: Characteristic<Peripheral>,
                    withResponse: Bool,
                    timeout: TimeInterval) throws
    
    func notify(_ notification: ((Data) -> ())?,
                for characteristic: Characteristic<Peripheral>,
                timeout: TimeInterval) throws
    
    func maximumTransmissionUnit(for peripheral: Peripheral) throws -> ATTMaximumTransmissionUnit 
}

public extension CentralProtocol {
    
    /// Scans for peripherals that are advertising services.
    @available(*, deprecated, message: "Use `stopScan()` instead")
    func scan(filterDuplicates: Bool = true,
              shouldContinueScanning: @escaping () -> (Bool),
              foundDevice: @escaping (ScanData<Peripheral, Advertisement>) -> ()) throws {
        
        DispatchQueue.global().async { [weak self] in
            while shouldContinueScanning() {
                usleep(10_000)
            }
            self?.stopScan()
        }
        
        try self.scan(filterDuplicates: filterDuplicates, foundDevice: foundDevice)
    }
    
    /// Scans for peripherals that are advertising services for the specified time interval.
    func scan(duration: TimeInterval, filterDuplicates: Bool = true) throws -> [ScanData<Peripheral, Advertisement>] {
        
        DispatchQueue.global().asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.stopScan()
        }
        
        var results = [Peripheral: ScanData<Peripheral, Advertisement>](minimumCapacity: 1)
        
        try scan(filterDuplicates: filterDuplicates,
                  foundDevice: { results[$0.peripheral] = $0 })
        
        return results.values.sorted(by: { $0.date < $1.date })
    }
}
    
// MARK: - Supporting Types

public protocol GATTAttribute {
    
    associatedtype Peripheral: Peer
    
    var identifier: UInt { get }
    
    var uuid: BluetoothUUID { get }
    
    var peripheral: Peripheral { get }
}

public struct Service <Peripheral: Peer> : GATTAttribute {
    
    public let identifier: UInt
    
    public let uuid: BluetoothUUID
    
    public let peripheral: Peripheral
    
    public let isPrimary: Bool
    
    public init(identifier: UInt,
                uuid: BluetoothUUID,
                peripheral: Peripheral,
                isPrimary: Bool = true) {
        
        self.identifier = identifier
        self.uuid = uuid
        self.peripheral = peripheral
        self.isPrimary = isPrimary
    }
}

public struct Characteristic <Peripheral: Peer> : GATTAttribute {
    
    public typealias Property = GATT.CharacteristicProperty
    
    public let identifier: UInt
    
    public let uuid: BluetoothUUID
    
    public let peripheral: Peripheral
    
    public let properties: BitMaskOptionSet<Property>
    
    public init(identifier: UInt,
                uuid: BluetoothUUID,
                peripheral: Peripheral,
                properties: BitMaskOptionSet<Property>) {
        
        self.identifier = identifier
        self.uuid = uuid
        self.peripheral = peripheral
        self.properties = properties
    }
}

public struct Descriptor <Peripheral: Peer>: GATTAttribute {
    
    public let identifier: UInt
    
    public let uuid: BluetoothUUID
    
    public let peripheral: Peripheral
    
    public init(identifier: UInt,
                uuid: BluetoothUUID,
                peripheral: Peripheral) {
        
        self.identifier = identifier
        self.uuid = uuid
        self.peripheral = peripheral
    }
}
