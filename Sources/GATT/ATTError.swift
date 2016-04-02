//
//  ATTError.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/1/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

/// Bluetooth Attribute Protocol (ATT) Errors
public enum ATTError: UInt8, ErrorType {
    
    /// The attribute handle given was not valid on this server.
    case InvalidHandle                              = 0x01
    
    /// The attribute cannot be read.
    case ReadNotPermitted                           = 0x02
    
    /// The attribute cannot be written.
    case WriteNotPermitted                          = 0x03
    
    /// The attribute PDU was invalid.
    case InvalidPDU                                 = 0x04
    
    /// The attribute requires authentication before it can be read or written.
    case Authentication                             = 0x05
    
    /// Attribute server does not support the request received from the client.
    case RequestNotSupported                        = 0x06
    
    /// Offset specified was past the end of the attribute.
    case InvalidOffset                              = 0x07
    
    /// The attribute requires authorization before it can be read or written.
    case InsufficientAuthorization                  = 0x08
    
    /// Too many prepare writes have been queued.
    case PrepareQueueFull                           = 0x09
    
    /// No attribute found within the given attribute handle range.
    case AttributeNotFound                          = 0x0A
    
    /// The attribute cannot be read or written using the *Read Blob Request*.
    case AttributeNotLong                           = 0x0B
    
    /// The *Encryption Key Size* used for encrypting this link is insufficient.
    case InsufficientEncryptionKeySize              = 0x0C
    
    /// The attribute value length is invalid for the operation.
    case InvalidAttributeValueLength                = 0x0D
    
    /// The attribute request that was requested has encountered an error that was unlikely,
    /// and therefore could not be completed as requested.
    case UnlikelyError                              = 0x0E
    
    /// The attribute requires encryption before it can be read or written.
    case InsufficientEncryption                     = 0x0F
    
    /// The attribute type is not a supported grouping attribute as defined by a higher layer specification.
    case UnsupportedGroupType                       = 0x10
    
    /// Insufficient Resources to complete the request.
    case InsufficientResources                      = 0x11
}

// MARK: - Linux Support
#if os(Linux)
    
    import BluetoothLinux
    
    public extension ATTError {
        
        init(_ error: BluetoothLinux.ATT.Error) {
            
            self = ATTError(rawValue: error.rawValue)!
        }
    }
    
// MARK: - Darwin Support
#elseif os(OSX) || os(iOS) || os(WatchOS) || os(tvOS)
    
    import CoreBluetooth
    
    public extension ATTError {
        
        init?(_ error: CBATTError) {
            
            guard let error = ATTError(rawValue: UInt8(error.rawValue))
                else { return nil }
            
            self = error
        }
    }
    
#endif



