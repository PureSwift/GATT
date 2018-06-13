//
//  DarwinDescriptor.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 6/13/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import Bluetooth

#if os(macOS) || os(iOS) || os(tvOS) || (os(watchOS) && swift(>=3.2))

import CoreBluetooth

internal enum DarwinDescriptor {
    
    /// Characteristic Extended Properties
    ///
    /// The string representation of the UUID for the extended properties descriptor.
    /// The corresponding value for this descriptor is an `NSNumber` object.
    case extendedProperties(NSNumber)
    
    /// Characteristic User Description Descriptor
    ///
    /// The string representation of the UUID for the user description descriptor.
    /// The corresponding value for this descriptor is an `NSString` object.
    case userDescription(NSString)
    
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
    case format(NSData)
    
    /// Characteristic Aggregate Format Descriptor
    ///
    /// The string representation of the UUID for the aggregate descriptor.
    case aggregateFormat(NSData)
    
    /// Characteristic Valid Range Descriptor
    ///
    /// Data representing the valid min/max values accepted for a characteristic.
    case validRange(NSData)
}

extension DarwinDescriptor {
    
    init?(uuid: BluetoothUUID, data: Data) {
        
        switch uuid {
        
        case .characteristicExtendedProperties:
            
            guard let descriptor = GATTCharacteristicExtendedProperties(byteValue: data)
                else { return nil }
            
            self = .extendedProperties(NSNumber(value: descriptor.properties.rawValue))
            
        case .characteristicUserDescription:
            
            guard let descriptor = GATTUserDescription(byteValue: data)
                else { return nil }
            
            self = .userDescription(descriptor.userDescription as NSString)
            
        case .characteristicFormat:
            
            self = .format(data as NSData)
            
            // FIXME: Implement all
            
        default:
            
            return nil
        }
    }
    
    var uuid: BluetoothUUID {
        
        switch self {
        case .extendedProperties: return .characteristicExtendedProperties
        case .userDescription: return .characteristicUserDescription
        case .clientConfiguration: return .clientCharacteristicConfiguration
        case .serverConfiguration: return .serverCharacteristicConfiguration
        case .format: return .characteristicFormat
        case .aggregateFormat: return .characteristicAggregateFormat
        case .validRange: return .validRange
        }
    }
    
    var value: AnyObject {
        
        switch self {
        case let .extendedProperties(value): return value
        case let .userDescription(value): return value
        case let .clientConfiguration(value): return value
        case let .serverConfiguration(value): return value
        case let .format(value): return value
        case let .aggregateFormat(value): return value
        case let .validRange(value): return value
        }
    }
}

internal extension CBMutableDescriptor {
    
    convenience init(_ descriptor: DarwinDescriptor) {
        
        self.init(type: descriptor.uuid.toCoreBluetooth(), value: descriptor.value)
    }
}

#endif
