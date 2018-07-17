//
//  DarwinPeer.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 7/14/18.
//

#if os(macOS) || os(iOS) || os(tvOS) || (os(watchOS) && swift(>=3.2))

import Foundation
import CoreBluetooth

internal extension CBCentral {
    
    var gattIdentifier: UUID {
        
        #if swift(>=3.2)
        if #available(macOS 10.13, *) {
            
            return (self as CBPeer).identifier
            
        } else {
            
            return self.value(forKey: "identifier") as! UUID
        }
        #elseif swift(>=3.0)
        return self.identifier
        #endif
    }
}

internal extension CBPeripheral {
    
    var gattIdentifier: UUID {
        
        #if swift(>=3.2)
        if #available(macOS 10.13, *) {
            
            return (self as CBPeer).identifier
            
        } else {
            
            return self.value(forKey: "identifier") as! UUID
        }
        #elseif swift(>=3.0)
        return self.identifier
        #endif
    }
}

#endif
