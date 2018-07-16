//
//  DarwinAdvertisementData.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 7/15/18.
//

import Foundation
import Bluetooth
import GATT

#if os(macOS) || os(iOS) || os(tvOS) || (os(watchOS) && swift(>=3.2))

import CoreBluetooth

internal extension AdvertisementData {
    
    init(_ coreBluetooth: [String: Any]) {
        
        self.localName = coreBluetooth[CBAdvertisementDataLocalNameKey] as? String
        
        self.manufacturerData = coreBluetooth[CBAdvertisementDataManufacturerDataKey] as? Data
        
        if let coreBluetoothServiceData = coreBluetooth[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] {
            
            var serviceData = [BluetoothUUID: Data](minimumCapacity: coreBluetoothServiceData.count)
            
            for (key, value) in coreBluetoothServiceData {
                
                let uuid = BluetoothUUID(coreBluetooth: key)
                
                serviceData[uuid] = value
            }
            
            self.serviceData = serviceData
            
        } else {
            
            self.serviceData = [:]
        }
        
        self.serviceUUIDs = (coreBluetooth[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.map { BluetoothUUID(coreBluetooth: $0) } ?? []
        
        self.overflowServiceUUIDs = (coreBluetooth[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID])?.map { BluetoothUUID(coreBluetooth: $0) } ?? []
        
        self.txPowerLevel = (coreBluetooth[CBAdvertisementDataTxPowerLevelKey] as? NSNumber)?.doubleValue
        
        self.isConnectable = (coreBluetooth[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue
        
        self.solicitedServiceUUIDs = (coreBluetooth[CBAdvertisementDataSolicitedServiceUUIDsKey] as? [CBUUID])?.map { BluetoothUUID(coreBluetooth: $0) } ?? []
    }
}

#endif
