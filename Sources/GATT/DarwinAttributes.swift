//
//  DarwinAttributes.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/2/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import Bluetooth

#if os(OSX) || os(iOS) || os(tvOS)
    
    import Foundation
    import CoreBluetooth
    
    internal protocol CoreBluetoothAttributeConvertible {
        
        //associatedtype CoreBluetoothCentralType
        associatedtype CoreBluetoothPeripheralType
        
        //init(_ CoreBluetooth: CoreBluetoothCentralType)
        func toCoreBluetooth() -> CoreBluetoothPeripheralType
    }
    
    extension Service: CoreBluetoothAttributeConvertible {
        
        /*
        init(_ CoreBluetooth: CBService) {
            
            self.UUID = Bluetooth.UUID(foundation: CoreBluetooth.UUID)
            self.primary = CoreBluetooth.isPrimary
            self.includedServices = [] // TODO: Implement included services
            self.characteristics = (CoreBluetooth.characteristics ?? []).map { Characteristic(foundation: $0) }
        }*/
        
        func toCoreBluetooth() -> CBMutableService {
            
            let service = CBMutableService(type: UUID.toFoundation(), primary: primary)
            
            service.characteristics = characteristics.map { $0.toCoreBluetooth() }
            
            return service
        }
    }
    
    extension Characteristic: CoreBluetoothAttributeConvertible {
        
        func toCoreBluetooth() -> CBMutableCharacteristic {
            
            let propertiesMask = CBCharacteristicProperties(rawValue: Int(properties.optionsBitmask()))
            
            let permissionsMask = CBAttributePermissions(rawValue: Int(permissions.optionsBitmask()))
            
            // http://stackoverflow.com/questions/29228244/issues-in-creating-writable-characteristic-in-core-bluetooth-framework#29229075
            // Characteristics with cached values must be read-only
            // Must set nil as value.
            
            let characteristic = CBMutableCharacteristic(type: UUID.toFoundation(), properties: propertiesMask, value: nil, permissions: permissionsMask)
            
            characteristic.descriptors = descriptors.map { $0.toCoreBluetooth() }
            
            return characteristic
        }
    }
    
    extension Descriptor: CoreBluetoothAttributeConvertible {
        
        func toCoreBluetooth() -> CBMutableDescriptor {
            
            let foundationUUID = UUID.toFoundation()
            
            // Only CBUUIDCharacteristicUserDescriptionString or CBUUIDCharacteristicFormatString is supported.
            switch foundationUUID.UUIDString {
                
            case CBUUIDCharacteristicUserDescriptionString:
                
                guard let string = String(UTF8Data: value)
                    else { fatalError("Could not parse string for CBMutableDescriptor from \(self)") }
                
                return CBMutableDescriptor(type: foundationUUID, value: string)
                
            case CBUUIDCharacteristicFormatString:
                
                return CBMutableDescriptor(type: foundationUUID, value: value.toFoundation())
                
            default: fatalError("Only CBUUIDCharacteristicUserDescriptionString or CBUUIDCharacteristicFormatString is supported. Unsupported UUID \(UUID).")
            }
        }
    }

#endif