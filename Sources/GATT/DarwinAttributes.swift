//
//  DarwinAttributes.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/2/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import Bluetooth

#if os(macOS) || os(iOS) || os(tvOS)
    
    import Foundation
    import CoreBluetooth
    
    internal protocol CoreBluetoothAttributeConvertible {
        
        //associatedtype CoreBluetoothCentralType
        associatedtype CoreBluetoothPeripheralType
        
        //init(_ CoreBluetooth: CoreBluetoothCentralType)
        func toCoreBluetooth() -> CoreBluetoothPeripheralType
    }
    
    extension Service: CoreBluetoothAttributeConvertible {
        
        func toCoreBluetooth() -> CBMutableService {
            
            let service = CBMutableService(type: uuid.toCoreBluetooth(), primary: primary)
            
            service.characteristics = characteristics.map { $0.toCoreBluetooth() }
            
            return service
        }
    }
    
    extension Characteristic: CoreBluetoothAttributeConvertible {
        
        func toCoreBluetooth() -> CBMutableCharacteristic {
            
            let propertyRawValue = CBCharacteristicProperties.RawValue.self
            
            let propertiesMask = CBCharacteristicProperties(rawValue: propertyRawValue.init(properties.rawValue))
            
            let permissionRawValue = CBAttributePermissions.RawValue.self
            
            let permissionsMask = CBAttributePermissions(rawValue: permissionRawValue.init(permissions.rawValue))
            
            // http://stackoverflow.com/questions/29228244/issues-in-creating-writable-characteristic-in-core-bluetooth-framework#29229075
            // Characteristics with cached values must be read-only
            // Must set nil as value.
            
            let characteristic = CBMutableCharacteristic(type: uuid.toCoreBluetooth(), properties: propertiesMask, value: nil, permissions: permissionsMask)
            
            characteristic.descriptors = descriptors.map { $0.toCoreBluetooth() }
            
            return characteristic
        }
    }
    
    extension Descriptor: CoreBluetoothAttributeConvertible {
        
        func toCoreBluetooth() -> CBMutableDescriptor {
            
            // Only CBUUIDCharacteristicUserDescriptionString or CBUUIDCharacteristicFormatString is supported.
            switch uuid.rawValue {
                
            case CBUUIDCharacteristicUserDescriptionString:
                
                guard let string = String(UTF8Data: value)
                    else { fatalError("Could not parse string for CBMutableDescriptor from \(self)") }
                
                return CBMutableDescriptor(type: uuid.toCoreBluetooth(), value: string)
                
            case CBUUIDCharacteristicFormatString:
                
                return CBMutableDescriptor(type: uuid.toCoreBluetooth(), value: value)
                
            default: fatalError("Only CBUUIDCharacteristicUserDescriptionString or CBUUIDCharacteristicFormatString is supported. Unsupported UUID \(uuid).")
            }
        }
    }
    
    internal protocol CoreBluetoothBitmaskConvertible: RawRepresentable {
        
        associatedtype CoreBluetoothBitmaskType: OptionSet
        
        /// Values that are supported in CoreBluetooth
        static var CoreBluetoothValues: [Self] { get }
        
        /// Convert from CoreBluetooth bitmask.
        static func from(CoreBluetooth: CoreBluetoothBitmaskType) -> [Self]
    }
    
    extension GATT.CharacteristicProperty: CoreBluetoothBitmaskConvertible {
        
        typealias CoreBluetoothBitmaskType = CBCharacteristicProperties
        
        static let CoreBluetoothValues: [GATT.CharacteristicProperty] = [.broadcast, .read, .writeWithoutResponse, .write, .notify, .indicate, .signedWrite, .extendedProperties]
        
        static func from(CoreBluetooth: CoreBluetoothBitmaskType) -> [GATT.CharacteristicProperty] {
            
            let bitmask = CoreBluetooth.rawValue
            
            var convertedValues: [GATT.CharacteristicProperty] = []
            
            for possibleValue in GATT.CharacteristicProperty.CoreBluetoothValues {
                
                let rawValue = CoreBluetoothBitmaskType.RawValue(possibleValue.rawValue)
                
                if rawValue & bitmask == rawValue {
                    
                    convertedValues.append(possibleValue)
                }
            }
            
            return convertedValues
        }
    }
    
    extension ATT.AttributePermission: CoreBluetoothBitmaskConvertible {
        
        typealias CoreBluetoothBitmaskType = CBAttributePermissions
        
        static let CoreBluetoothValues = [.read, .write] + ATT.AttributePermission.encrypt
        
        static func from(CoreBluetooth: CoreBluetoothBitmaskType) -> [ATT.AttributePermission] {
            
            let bitmask = CoreBluetooth.rawValue
            
            var convertedValues: [ATT.AttributePermission] = []
            
            for possibleValue in ATT.AttributePermission.CoreBluetoothValues {
                
                let rawValue = CoreBluetoothBitmaskType.RawValue(possibleValue.rawValue)
                
                if rawValue & bitmask == rawValue {
                    
                    convertedValues.append(possibleValue)
                }
            }
            
            return convertedValues
        }
    }

#endif
