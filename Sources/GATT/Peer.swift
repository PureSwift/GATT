//
//  Peer.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/2/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import struct SwiftFoundation.UUID

#if os(OSX)
    public typealias PeerIdentifier = SwiftFoundation.UUID
#elseif os(Linux)
    public typealias PeerIdentifier = Bluetooth.Address
#endif

public protocol Peer {
    
    /// Unique identifier of the peer.
    var identifier: PeerIdentifier { get }
    
    /// The maximum amount of data, in bytes, that the central can receive in a single notification or indication.
    var maximumTranssmissionUnit: Int { get }
}

/// Central Peer
///
/// Represents remote central devices that have connected to an app implementing the peripheral role on a local device.
public struct Central: Peer {
    
    public let identifier: PeerIdentifier
    
    public let maximumTranssmissionUnit: Int
    
    internal init(identifier: PeerIdentifier, maximumTranssmissionUnit: Int) {
        
        self.identifier = identifier
        self.maximumTranssmissionUnit = maximumTranssmissionUnit
    }
}