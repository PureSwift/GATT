//
//  DarwinDescriptor.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 6/13/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import Bluetooth

#if os(macOS) || os(iOS)

import CoreBluetooth

internal enum DarwinDescriptor {
    
    /// Characteristic Format Descriptor
    ///
    /// The string representation of the UUID for the presentation format descriptor.
    /// The corresponding value for this descriptor is an `NSData` object
    case format(NSData)
    
    /// Characteristic User Description Descriptor
    ///
    /// The string representation of the UUID for the user description descriptor.
    /// The corresponding value for this descriptor is an `NSString` object.
    case userDescription(NSString)
}

extension DarwinDescriptor {
    
    init?(uuid: BluetoothUUID, data: Data) {
        
        switch uuid {
        
        case .characteristicUserDescription:
            
            guard let userDescription = String(data: data, encoding: .utf8)
                else { return nil }
            
            self = .userDescription(userDescription as NSString)
            
        case .characteristicFormat:
            
            self = .format(data as NSData)
            
            /*
            
        case BluetoothUUID.characteristicExtendedProperties:
            
            guard let descriptor = GATTCharacteristicExtendedProperties(data: data)
                else { return nil }
            
            self = .extendedProperties(NSNumber(value: descriptor.properties.rawValue))
            
        case BluetoothUUID.clientCharacteristicConfiguration:
            
            guard let descriptor = GATTClientCharacteristicConfiguration(data: data)
                else { return nil }
            
            self = .clientConfiguration(descriptor.configuration.rawValue as NSNumber)
 
            */
            
        default:
            
            return nil
        }
    }
    
    var uuid: BluetoothUUID {
        
        switch self {
        case .format: return .characteristicFormat
        case .userDescription: return .characteristicUserDescription
        }
    }
    
    var value: AnyObject {
        
        switch self {
        case let .format(value): return value
        case let .userDescription(value): return value
        }
    }
}

internal extension CBMutableDescriptor {
    
    convenience init(_ descriptor: DarwinDescriptor) {
        
        self.init(type: CBUUID(descriptor.uuid), value: descriptor.value)
    }
}

internal extension CBDescriptor {
    
    /// Only the characteristic user description descriptor and the characteristic format descriptor
    /// are supported for descriptors for use in local Peripherals.
    static var supportedUUID: Set<BluetoothUUID> {
        return [.characteristicUserDescription, .characteristicFormat]
    }
}

#endif
