//
//  Descriptor.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 1/6/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Bluetooth

/// Represents a descriptor of a peripheral’s characteristic.
public enum CharacteristicDescriptorValue {
    
    /// Characteristic Extended Properties
    case extendedProperties(GATT.CharacteristicExtendedProperty)
    
    /// Characteristic User Description Descriptor
    ///
    /// The UUID for the user description descriptor
    case userDescription(BluetoothUUID)
    
    /// Client Characteristic Configuration Descriptor
    case clientConfiguration(BluetoothUUID)
    
    /// Server Characteristic Configuration Descriptor
    case serverConfiguration(BluetoothUUID)
    
    /// Characteristic Format Descriptor
    case format()
    
    /// Characteristic Aggregate Format Descriptor
    case aggregateFormat()
}

#if os(macOS) || os(iOS) || os(watchOS)

internal enum DarwinCharacteristicDescriptorValue {
    
    /// Characteristic Extended Properties
    ///
    /// The string representation of the UUID for the extended properties descriptor.
    /// The corresponding value for this descriptor is an `NSNumber` object.
    case extendedProperties(NSNumber)
    
    /// Characteristic User Description Descriptor
    ///
    /// The string representation of the UUID for the user description descriptor.
    /// The corresponding value for this descriptor is an `NSString` object.
    case userDescription(String)
    
    /// Client Characteristic Configuration Descriptor
    ///
    /// The string representation of the UUID for the client configuration descriptor.
    /// The corresponding value for this descriptor is an `NSNumber` object.
    case clientConfiguration(NSNumber)
    
    /// Server Characteristic Configuration Descriptor
    ///
    /// The string representation of the UUID for the server configuration descriptor.
    /// The corresponding value for this descriptor is an `NSNumber` object.
    case serverConfiguration(NSNumber)
    
    /// Characteristic Format Descriptor
    ///
    /// The string representation of the UUID for the presentation format descriptor.
    /// The corresponding value for this descriptor is an `NSData` object
    case format(Data)
    
    /// Characteristic Aggregate Format Descriptor
    ///
    /// The string representation of the UUID for the aggregate descriptor.
    case aggregateFormat(Data)
}

#endif
