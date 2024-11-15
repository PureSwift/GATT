//
//  CentralAttributes.swift
//  
//
//  Created by Alsey Coleman Miller on 1/11/21.
//

import Bluetooth

/// GATT Central Attribute protocol
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

public struct Service <Peripheral: Peer, ID: Hashable> : GATTCentralAttribute, Hashable, Sendable where ID: Sendable {
    
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

extension Service: Identifiable { }

public struct Characteristic <Peripheral: Peer, ID: Hashable> : GATTCentralAttribute, Hashable, Sendable where ID: Sendable {
    
    public typealias Properties = CharacteristicProperties
    
    public let id: ID
    
    public let uuid: BluetoothUUID
    
    public let peripheral: Peripheral
    
    public let properties: Properties
    
    public init(
        id: ID,
        uuid: BluetoothUUID,
        peripheral: Peripheral,
        properties: Properties
    ) {
        self.id = id
        self.uuid = uuid
        self.peripheral = peripheral
        self.properties = properties
    }
}

extension Characteristic: Identifiable { }

public struct Descriptor <Peripheral: Peer, ID: Hashable>: GATTCentralAttribute, Hashable, Sendable where ID: Sendable {
    
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

extension Descriptor: Identifiable { }
