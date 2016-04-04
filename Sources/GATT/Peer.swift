//
//  Peer.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/2/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

#if os(OSX) || os(iOS)
    import CoreBluetooth
    import struct SwiftFoundation.UUID
    public typealias PeerIdentifier = SwiftFoundation.UUID
#elseif os(Linux)
    import struct Bluetooth.Address
    public typealias PeerIdentifier = Bluetooth.Address
#endif

public protocol Peer {
    
    /// Unique identifier of the peer.
    var identifier: PeerIdentifier { get }
}

/// Central Peer
///
/// Represents a remote central device that has connected to an app implementing the peripheral role on a local device.
public struct Central: Peer {
    
    public let identifier: PeerIdentifier
    
    /// The maximum amount of data, in bytes, that the central can receive in a single notification or indication.
    public let maximumTranssmissionUnit: Int
    
    internal init(identifier: PeerIdentifier, maximumTranssmissionUnit: Int) {
        
        self.identifier = identifier
        self.maximumTranssmissionUnit = maximumTranssmissionUnit
    }
}

#if os(OSX) || os(iOS)
    
    extension Central {
        
        init(_ central: CBCentral) {
            
            self.identifier = SwiftFoundation.UUID(foundation: central.identifier)
            self.maximumTranssmissionUnit = central.maximumUpdateValueLength
        }
    }
    
#endif

/// Peripheral Peer
///
/// Represents a remote peripheral device that has been discovered.
public struct Peripheral: Peer {
    
    public let identifier: PeerIdentifier
}

#if os(OSX) || os(iOS)
    
    extension Peripheral {
        
        init(_ central: CBPeripheral) {
            
            self.identifier = SwiftFoundation.UUID(foundation: central.identifier)
        }
    }

#endif


