//
//  CharacteristicProperty.swift
//  
//
//  Created by Alsey Coleman Miller on 10/23/20.
//

import Foundation
@_exported import Bluetooth
#if canImport(BluetoothGATT)
@_exported import BluetoothGATT
public typealias CharacteristicProperty = GATTCharacteristicProperty
#else
/// GATT Characteristic Properties Bitfield values
public enum CharacteristicProperty: UInt8, BitMaskOption {
    
    case broadcast              = 0x01
    case read                   = 0x02
    case writeWithoutResponse   = 0x04
    case write                  = 0x08
    case notify                 = 0x10
    case indicate               = 0x20
    
    /// Characteristic supports write with signature
    case signedWrite            = 0x40 // BT_GATT_CHRC_PROP_AUTH
    
    case extendedProperties     = 0x80
}

// MARK: CustomStringConvertible

extension CharacteristicProperty: CustomStringConvertible {
    
    public var description: String {
        
        switch self {
        case .broadcast:                return "Broadcast"
        case .read:                     return "Read"
        case .write:                    return "Write"
        case .writeWithoutResponse:     return "Write without Response"
        case .notify:                   return "Notify"
        case .indicate:                 return "Indicate"
        case .signedWrite:              return "Signed Write"
        case .extendedProperties:       return "Extended Properties"
        }
    }
}
#endif
