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
/// Implementation varies by operating system and framework.
public protocol CentralProtocol: AnyObject {
    
    /// Central Peripheral Type
    associatedtype Peripheral: Peer
    
    /// Central Advertisement Type
    associatedtype Advertisement: AdvertisementData
    
    /// Central Attribute ID (Handle)
    associatedtype AttributeID: Hashable
    
    /// 
    var log: ((String) -> ())? { get set }
     
    /// Scans for peripherals that are advertising services.
    func scan(filterDuplicates: Bool,
              _ foundDevice: @escaping (Result<ScanData<Peripheral, Advertisement>, Error>) -> ())
    
    /// Stops scanning for peripherals.
    func stopScan()
    
    ///
    var isScanning: Bool { get }
    
    ///
    var scanningChanged: ((Bool) -> ())? { get set }
    
    ///
    func connect(to peripheral: Peripheral,
                 timeout: TimeInterval,
                 completion: @escaping (Result<Void, Error>) -> ())
    
    ///
    func disconnect(_ peripheral: Peripheral)
    
    ///
    func disconnectAll()
    
    ///
    var didDisconnect: ((Peripheral) -> ())? { get set }
    
    ///
    func discoverServices(
        _ services: [BluetoothUUID],
        for peripheral: Peripheral,
        timeout: TimeInterval,
        completion: @escaping (Result<[Service<Peripheral, AttributeID>], Error>) -> ()
    )
    
    ///
    func discoverCharacteristics(
        _ characteristics: [BluetoothUUID],
        for service: Service<Peripheral, AttributeID>,
        timeout: TimeInterval,
        completion: @escaping (Result<[Characteristic<Peripheral, AttributeID>], Error>) -> ()
    )
    
    ///
    func readValue(
        for characteristic: Characteristic<Peripheral, AttributeID>,
        timeout: TimeInterval,
        completion: @escaping (Result<Data, Error>) -> ()
    )
    
    ///
    func writeValue(
        _ data: Data,
        for characteristic: Characteristic<Peripheral, AttributeID>,
        withResponse: Bool,
        timeout: TimeInterval,
        completion: @escaping (Result<Void, Error>) -> ()
    )
    
    ///
    func notify(_ notification: ((Data) -> ())?,
                for characteristic: Characteristic<Peripheral, AttributeID>,
                timeout: TimeInterval,
                completion: @escaping (Result<Void, Error>) -> ())
    
    ///
    func maximumTransmissionUnit(for peripheral: Peripheral,
                                 completion: @escaping (Result<MaximumTransmissionUnit, Error>) -> ())
}

// MARK: - Supporting Types

public protocol GATTCentralAttribute {
    
    associatedtype Peripheral: Peer
    
    associatedtype ID
    
    /// Attribute identifier, usually the ATT handle.
    var id: ID { get }
    
    /// GATT Attribute UUID.
    var uuid: BluetoothUUID { get }
    
    /// Peripheral this attribute was read from.
    var peripheral: Peripheral { get }
}

//extension GATTCentralAttribute: Identifiable where ID: Hashable { }

public struct Service <Peripheral: Peer, ID: Hashable> : GATTCentralAttribute {
    
    public let id: ID
    
    public let uuid: BluetoothUUID
    
    public let peripheral: Peripheral
    
    /// A Boolean value that indicates whether the type of service is primary or secondary.
    public let isPrimary: Bool
    
    public init(id: ID,
                uuid: BluetoothUUID,
                peripheral: Peripheral,
                isPrimary: Bool = true) {
        
        self.id = id
        self.uuid = uuid
        self.peripheral = peripheral
        self.isPrimary = isPrimary
    }
}

public struct Characteristic <Peripheral: Peer, ID: Hashable> : GATTCentralAttribute {
    
    public typealias Property = CharacteristicProperty
    
    public let id: ID
    
    public let uuid: BluetoothUUID
    
    public let peripheral: Peripheral
    
    public let properties: BitMaskOptionSet<Property>
    
    public init(id: ID,
                uuid: BluetoothUUID,
                peripheral: Peripheral,
                properties: BitMaskOptionSet<Property>) {
        
        self.id = id
        self.uuid = uuid
        self.peripheral = peripheral
        self.properties = properties
    }
}

public struct Descriptor <Peripheral: Peer, ID: Hashable>: GATTCentralAttribute {
    
    public let id: ID
    
    public let uuid: BluetoothUUID
    
    public let peripheral: Peripheral
    
    public init(id: ID,
                uuid: BluetoothUUID,
                peripheral: Peripheral) {
        
        self.id = id
        self.uuid = uuid
        self.peripheral = peripheral
    }
}
