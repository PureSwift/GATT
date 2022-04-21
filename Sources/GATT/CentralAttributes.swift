//
//  CentralAttributes.swift
//  
//
//  Created by Alsey Coleman Miller on 1/11/21.
//

import Foundation
import Bluetooth

/// GATT Central Attribute protocol
public protocol GATTCentralAttribute: Identifiable {
    
    associatedtype Peripheral: Peer
    
    associatedtype ID
    
    /// Attribute identifier, usually the ATT handle.
    var id: ID { get }
    
    /// GATT Attribute UUID.
    var uuid: BluetoothUUID { get }
    
    /// Peripheral this attribute was read from.
    var peripheral: Peripheral { get }
}

public struct Service <Peripheral: Peer, ID: Hashable> : GATTCentralAttribute, Hashable {
    
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

public struct Characteristic <Peripheral: Peer, ID: Hashable> : GATTCentralAttribute, Hashable {
    
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

public struct Descriptor <Peripheral: Peer, ID: Hashable>: GATTCentralAttribute, Hashable {
    
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

