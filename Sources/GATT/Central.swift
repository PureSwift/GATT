//
//  GATTCentral.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 7/17/18.
//

import Foundation
import Bluetooth

/// Central Peer
///
/// Represents a remote central device that has connected to an app implementing the peripheral role on a local device.
public struct Central: Peer {
    
    public let identifier: Bluetooth.Address
    
    public init(identifier: Bluetooth.Address) {
        
        self.identifier = identifier
    }
}
