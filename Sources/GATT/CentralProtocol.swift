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
              shouldContinueScanning: () -> (Bool),
              foundDevice: @escaping (ScanData<Peripheral, Advertisement>) -> ()) throws
    
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
    
    func scan(duration: TimeInterval, filterDuplicates: Bool = true) throws -> [ScanData<Peripheral, Advertisement>] {
        
        let endDate = Date() + duration
        
        var results = [Peripheral: ScanData<Peripheral, Advertisement>](minimumCapacity: 1)
        
        try scan(filterDuplicates: filterDuplicates,
                  shouldContinueScanning: { Date() < endDate },
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
