//
//  DarwinPeer.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 7/14/18.
//

#if canImport(CoreBluetooth)
import Foundation
import Bluetooth
import CoreBluetooth

internal extension CBCentral {
    
    var gattIdentifier: UUID {
        
        if #available(macOS 10.13, *) {
            return (self as CBPeer).identifier
        } else {
            return self.value(forKey: "identifier") as! UUID
        }
    }
}

internal extension CBPeripheral {
    
    var gattIdentifier: UUID {
        
        if #available(macOS 10.13, *) {
            return (self as CBPeer).identifier
        } else {
            return self.value(forKey: "identifier") as! UUID
        }
    }
}
#endif
