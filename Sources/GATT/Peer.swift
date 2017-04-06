//
//  Peer.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/2/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

#if os(OSX) || os(iOS)
    import CoreBluetooth
    import struct Foundation.UUID
    public typealias PeerIdentifier = Foundation.UUID
#elseif os(Linux)
    import BluetoothLinux
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
    
    internal init(identifier: PeerIdentifier) {
        
        self.identifier = identifier
    }
}

#if os(Linux)
    
    extension Central {
        
        init(socket: BluetoothLinux.L2CAPSocket) {
            
            self.identifier = socket.address
        }
    }

#elseif XcodeLinux
    
    import BluetoothLinux
    
    extension Central {
        
        init(socket: L2CAPSocket) {
            
            fatalError("Linux Only")
        }
    }

#endif

#if os(OSX) || os(iOS)
    
    extension Central {
        
        init(_ central: CBCentral) {
            
            self.identifier = central.identifier
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
            
            self.identifier = central.identifier
        }
    }

#endif


