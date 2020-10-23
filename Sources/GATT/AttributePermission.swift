//
//  AttributePermission.swift
//  
//
//  Created by Alsey Coleman Miller on 10/23/20.
//

import Foundation
@_exported import Bluetooth
#if canImport(BluetoothGATT)
@_exported import BluetoothGATT
public typealias AttributePermission = ATTAttributePermission
#else
/// ATT attribute permission bitfield values. Permissions are grouped as
/// "Access", "Encryption", "Authentication", and "Authorization". A bitmask of
/// permissions is a byte that encodes a combination of these.
public enum AttributePermission: UInt8, BitMaskOption {
    
    // Access
    case read                                       = 0x01
    case write                                      = 0x02
    
    // Encryption
    public static let encrypt                       = BitMaskOptionSet<AttributePermission>([.readEncrypt, .writeEncrypt])
    case readEncrypt                                = 0x04
    case writeEncrypt                               = 0x08
    
    // The following have no effect on Darwin
    
    // Authentication
    public static let  authentication               = BitMaskOptionSet<AttributePermission>([.readAuthentication, .writeAuthentication])
    case readAuthentication                         = 0x10
    case writeAuthentication                        = 0x20
    
    // Authorization
    case authorized                                 = 0x40
    case noAuthorization                            = 0x80
}

public extension AttributePermission {
    
    var name: String {
        
        switch self {
        case .read: return "Read"
        case .write: return "Write"
        case .readEncrypt: return "Read Encrypt"
        case .writeEncrypt: return "Write Encrypt"
        case .readAuthentication: return "Read Authentication"
        case .writeAuthentication: return "Write Authentication"
        case .authorized: return "Authorized"
        case .noAuthorization: return "No Authorization"
        }
    }
}

// MARK: CustomStringConvertible

extension AttributePermission: CustomStringConvertible {
    
    public var description: String {
        
        return name
    }
}
#endif
