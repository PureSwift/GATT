//
//  DarwinAttributes.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/2/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import Bluetooth

#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
    
    import Foundation
    import CoreBluetooth
    
    internal protocol CoreBluetoothAttributeConvertible {
        
        //associatedtype CoreBluetoothCentralType
        associatedtype CoreBluetoothPeripheralType
        
        //init(_ CoreBluetooth: CoreBluetoothCentralType)
        func toCoreBluetooth() -> CoreBluetoothPeripheralType
    }
    
    #if os(macOS) || os(iOS) // watchOS and tvOS only support Central mode
    extension GATT.Service: CoreBluetoothAttributeConvertible {
        
        func toCoreBluetooth() -> CBMutableService {
            
            let service = CBMutableService(type: uuid.toCoreBluetooth(), primary: primary)
            
            service.characteristics = characteristics.map { $0.toCoreBluetooth() }
            
            return service
        }
    }
    
    extension GATT.Characteristic: CoreBluetoothAttributeConvertible {
        
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
    
    extension GATT.Descriptor: CoreBluetoothAttributeConvertible {
        
        func toCoreBluetooth() -> CBMutableDescriptor {
            
            // Only CBUUIDCharacteristicUserDescriptionString or CBUUIDCharacteristicFormatString is supported.
            switch uuid.rawValue {
                
            case CBUUIDCharacteristicUserDescriptionString:
                
                guard let string = String(UTF8Data: value)
                    else { fatalError("Could not parse string for \(CBMutableDescriptor.self) from \(self)") }
                
                return CBMutableDescriptor(type: uuid.toCoreBluetooth(), value: string)
                
            case CBUUIDCharacteristicFormatString:
                
                return CBMutableDescriptor(type: uuid.toCoreBluetooth(), value: value)
                
            default:
                
                fatalError("Only \(CBUUIDCharacteristicUserDescriptionString) or \(CBUUIDCharacteristicFormatString) is supported. Unsupported UUID \(uuid).")
            }
        }
    }
        
    #endif
    
    internal protocol CoreBluetoothBitmaskConvertible: BitMaskOption {
        
        associatedtype CoreBluetoothBitmaskType: OptionSet
        
        /// Values that are supported in CoreBluetooth
        static var coreBluetoothValues: [Self] { get }
        
        /// Convert from CoreBluetooth bitmask.
        static func from(coreBluetooth: CoreBluetoothBitmaskType) -> BitMaskOptionSet<Self>
    }
    
    extension GATT.CharacteristicProperty: CoreBluetoothBitmaskConvertible {
        
        typealias CoreBluetoothBitmaskType = CBCharacteristicProperties
        
        static let coreBluetoothValues: [GATT.CharacteristicProperty] = [
            .broadcast,
            .read,
            .writeWithoutResponse,
            .write,
            .notify,
            .indicate,
            .signedWrite,
            .extendedProperties
        ]
        
        static func from(coreBluetooth: CoreBluetoothBitmaskType) -> BitMaskOptionSet<GATT.CharacteristicProperty> {
            
            let bitmask = coreBluetooth.rawValue
            
            var convertedValues = BitMaskOptionSet<GATT.CharacteristicProperty>()
            
            for possibleValue in GATT.CharacteristicProperty.coreBluetoothValues {
                
                let rawValue = CoreBluetoothBitmaskType.RawValue(possibleValue.rawValue)
                
                if rawValue & bitmask == rawValue {
                    
                    convertedValues.insert(possibleValue)
                }
            }
            
            return convertedValues
        }
    }
    
    extension ATT.AttributePermission: CoreBluetoothBitmaskConvertible {
        
        typealias CoreBluetoothBitmaskType = CBAttributePermissions
        
        static let coreBluetoothValues: [ATT.AttributePermission] = [.read, .write] + ATT.AttributePermission.encrypt
        
        static func from(coreBluetooth: CoreBluetoothBitmaskType) -> BitMaskOptionSet<ATT.AttributePermission> {
            
            let bitmask = coreBluetooth.rawValue
            
            var convertedValues = BitMaskOptionSet<ATT.AttributePermission>()
            
            for possibleValue in ATT.AttributePermission.coreBluetoothValues {
                
                let rawValue = CoreBluetoothBitmaskType.RawValue(possibleValue.rawValue)
                
                if rawValue & bitmask == rawValue {
                    
                    convertedValues.insert(possibleValue)
                }
            }
            
            return convertedValues
        }
    }

#endif
