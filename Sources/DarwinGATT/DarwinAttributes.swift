//
//  DarwinAttributes.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/2/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

// watchOS and tvOS only support Central mode
#if (os(macOS) || os(iOS)) && canImport(BluetoothGATT)
import Foundation
import Bluetooth
import BluetoothGATT
import CoreBluetooth

internal protocol CoreBluetoothAttributeConvertible {
    
    associatedtype CoreBluetoothPeripheralType
    
    func toCoreBluetooth() -> CoreBluetoothPeripheralType
}

extension GATTAttribute.Service: CoreBluetoothAttributeConvertible where Data == Foundation.Data {
    
    func toCoreBluetooth() -> CBMutableService {
        
        let service = CBMutableService(type: CBUUID(uuid), primary: isPrimary)
        service.characteristics = characteristics.map { $0.toCoreBluetooth() }
        return service
    }
}

extension GATTAttribute.Characteristic: CoreBluetoothAttributeConvertible where Data == Foundation.Data {
    
    func toCoreBluetooth() -> CBMutableCharacteristic {
        
        // http://stackoverflow.com/questions/29228244/issues-in-creating-writable-characteristic-in-core-bluetooth-framework#29229075
        // Characteristics with cached values must be read-only
        // Must set nil as value.
        
        let characteristic = CBMutableCharacteristic(
            type: CBUUID(uuid),
            properties: CBCharacteristicProperties(rawValue: .init(properties.rawValue)),
            value: nil,
            permissions: CBAttributePermissions(rawValue: .init(permissions.rawValue))
        )
        
        characteristic.descriptors = descriptors
            .filter { CBMutableDescriptor.supportedUUID.contains($0.uuid) }
            .map { $0.toCoreBluetooth() }
        
        return characteristic
    }
}

extension GATTAttribute.Descriptor: CoreBluetoothAttributeConvertible where Data == Foundation.Data {
    
    func toCoreBluetooth() -> CBMutableDescriptor {
        
        /*
         Only the Characteristic User Description and Characteristic Presentation Format descriptors are currently supported. The Characteristic Extended Properties and Client Characteristic Configuration descriptors will be created automatically upon publication of the parent service, depending on the properties of the characteristic itself
         
         e.g.
         ```
         Assertion failure in -[CBMutableDescriptor initWithType:value:], /SourceCache/CoreBluetooth_Sim/CoreBluetooth-59.3/CBDescriptor.m:25
         ```
         */
        
        guard let descriptor = CBMutableDescriptor(uuid: self.uuid, data: self.value)
            else { fatalError("Unsupported \(CBDescriptor.self) \(uuid)") }
        
        return descriptor
    }
}

#endif
