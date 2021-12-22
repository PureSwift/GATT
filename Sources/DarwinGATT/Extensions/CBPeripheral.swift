//
//  CBPeripheral.swift
//  
//
//  Created by Alsey Coleman Miller on 22/12/21.
//

#if canImport(CoreBluetooth)
import Foundation
import CoreBluetooth

internal extension CBPeripheral {
    
    var id: UUID {
        if #available(macOS 10.13, *) {
            return (self as CBPeer).identifier
        } else {
            return self.value(forKey: "identifier") as! UUID
        }
    }
    
    var mtuLength: NSNumber {
        return self.value(forKey: "mtuLength") as! NSNumber
    }
}
#endif
