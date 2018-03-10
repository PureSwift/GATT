//
//  Peer.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/2/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
    import CoreBluetooth
    import struct Foundation.UUID
    public typealias PeerIdentifier = Foundation.UUID
#elseif os(Linux)
    import BluetoothLinux
    import struct Bluetooth.Address
    public typealias PeerIdentifier = Bluetooth.Address
#endif

public protocol Peer: Hashable {
    
    /// Unique identifier of the peer.
    var identifier: PeerIdentifier { get }
}

extension Peer {
    
    public static func == (lhs: Self, rhs: Self) -> Bool {
        
        return lhs.identifier == rhs.identifier
    }
}

public extension Peer {
    
    public var hashValue: Int {
        
        return identifier.hashValue
    }
}

/// Central Peer
///
/// Represents a remote central device that has connected to an app implementing the peripheral role on a local device.
public struct Central: Peer {
    
    public let identifier: PeerIdentifier
}

extension Central: CustomStringConvertible {
    
    public var description: String {
        
        return identifier.description
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

#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
    
    @available(macOS 10.13, *)
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

extension Peripheral: CustomStringConvertible {
    
    public var description: String {
        
        return identifier.description
    }
}

#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
    
    @available(macOS 10.13, *)
    extension Peripheral {
        
        init(_ peripheral: CBPeripheral) {
            
            self.identifier = peripheral.identifier
        }
    }

#endif
