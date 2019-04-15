//
//  Peer.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/2/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

/// Bluetooth LE Peer (Central, Peripheral)
public protocol Peer: Hashable, CustomStringConvertible {
    
    associatedtype Identifier: Hashable, CustomStringConvertible
    
    /// Unique identifier of the peer.
    var identifier: Identifier { get }
}

public extension Peer {
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        
        return lhs.identifier == rhs.identifier
    }
    
    #if swift(>=4.2)
    func hash(into hasher: inout Hasher) {
        identifier.hash(into: &hasher)
    }
    #else
    var hashValue: Int {
        return identifier.hashValue
    }
    #endif
    
    var description: String {
        
        return identifier.description
    }
}
