//
//  CBCentral.swift
//  
//
//  Created by Alsey Coleman Miller on 22/12/21.
//

#if canImport(CoreBluetooth)
import Foundation
import CoreBluetooth

internal extension CBCentral {
    
    var id: UUID {
        if #available(macOS 10.13, *) {
            return (self as CBPeer).identifier
        } else {
            return self.value(forKey: "identifier") as! UUID
        }
    }
}
#endif
