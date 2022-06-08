//
//  DarwinDescriptor.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 6/13/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

#if canImport(CoreBluetooth)
import Foundation
import CoreBluetooth
import Bluetooth

/// Darwin Characteristic Descriptor
///
/// [Documentation](https://developer.apple.com/documentation/corebluetooth/cbuuid/characteristic_descriptors)
internal enum DarwinDescriptor {
    
    /// Characteristic Extended Properties
    ///
    /// The corresponding value for this descriptor is an `NSNumber` object.
    case extendedProperties(NSNumber)
        
    /// Characteristic User Description Descriptor
    ///
    /// The corresponding value for this descriptor is an `NSString` object.
    case userDescription(NSString)
    
    /// Characteristic Format Descriptor
    ///
    /// The corresponding value for this descriptor is an `NSData` object
    case format(NSData)
    
    /// Characteristic Aggregate Format
    ///
    case aggregateFormat(NSData)
    
    /// Client Characteristic Configuration
    ///
    /// The corresponding value for this descriptor is an `NSNumber` object.
    case clientConfiguration(NSNumber)
    
    /// Server Characteristic Configuration
    ///
    /// The corresponding value for this descriptor is an `NSNumber` object.
    case serverConfiguration(NSNumber)
    
}

extension DarwinDescriptor {
    
    init?(_ descriptor: CBDescriptor) {
        let uuid = BluetoothUUID(descriptor.uuid)
        switch uuid {
        case .characteristicUserDescription:
            guard let userDescription = descriptor.value as? NSString
                else { return nil }
            self = .userDescription(userDescription)
        case .characteristicFormat:
            guard let data = descriptor.value as? NSData
                else { return nil }
            self = .format(data)
        case .characteristicExtendedProperties:
            guard let data = descriptor.value as? NSNumber
                else { return nil }
            self = .extendedProperties(data)
        case .characteristicAggregateFormat:
            guard let data = descriptor.value as? NSData
                else { return nil }
            self = .aggregateFormat(data)
        case .clientCharacteristicConfiguration:
            guard let data = descriptor.value as? NSNumber
                else { return nil }
            self = .clientConfiguration(data)
        case .serverCharacteristicConfiguration:
            guard let data = descriptor.value as? NSNumber
                else { return nil }
            self = .serverConfiguration(data)
        default:
            return nil
        }
        assert(self.uuid == uuid)
    }
    
    var uuid: BluetoothUUID {
        switch self {
        case .format: return .characteristicFormat
        case .userDescription: return .characteristicUserDescription
        case .extendedProperties: return .characteristicExtendedProperties
        case .aggregateFormat: return .characteristicAggregateFormat
        case .clientConfiguration: return .clientCharacteristicConfiguration
        case .serverConfiguration: return .serverCharacteristicConfiguration
        }
    }
    
    var value: AnyObject {
        switch self {
        case let .format(value): return value
        case let .userDescription(value): return value
        case let .aggregateFormat(value): return value
        case let .extendedProperties(value): return value
        case let .clientConfiguration(value): return value
        case let .serverConfiguration(value): return value
        }
    }
    
    var data: Data {
        switch self {
        case let .userDescription(value):
            return Data((value as String).utf8)
        case let .format(value):
            return value as Data
        case let .aggregateFormat(value):
            return value as Data
        case let .extendedProperties(value):
            return Data([value.uint8Value])
        case let .clientConfiguration(value):
            let bytes = value.uint16Value.littleEndian.bytes
            return Data([bytes.0, bytes.1])
        case let .serverConfiguration(value):
            let bytes = value.uint16Value.littleEndian.bytes
            return Data([bytes.0, bytes.1])
        }
    }
}

#if (os(macOS) || os(iOS)) && canImport(BluetoothGATT)
internal extension CBMutableDescriptor {
    
    /// Only the characteristic user description descriptor and the characteristic format descriptor
    /// are supported for descriptors for use in local Peripherals.
    static var supportedUUID: Set<BluetoothUUID> {
        return [.characteristicUserDescription, .characteristicFormat]
    }
    
    convenience init?(_ descriptor: DarwinDescriptor) {
        guard Self.supportedUUID.contains(descriptor.uuid) else { return nil }
        self.init(type: CBUUID(descriptor.uuid), value: descriptor.value)
    }
    
    convenience init?(uuid: BluetoothUUID, data: Data) {
        let descriptor: DarwinDescriptor
        switch uuid {
        case .characteristicUserDescription:
            guard let userDescription = String(data: data, encoding: .utf8)
                else { return nil }
            descriptor = .userDescription(userDescription as NSString)
        case .characteristicFormat:
            descriptor = .format(data as NSData)
        default:
            assert(Self.supportedUUID.contains(uuid) == false)
            return nil
        }
        self.init(descriptor)
    }
}
#endif
#endif
