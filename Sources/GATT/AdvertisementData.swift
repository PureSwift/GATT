//
//  AdvertisementData.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 3/9/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import Bluetooth

public struct AdvertisementData {
    
    /// The local name of a peripheral.
    public let localName: String?
    
    /// The Manufacturer data of a peripheral.
    public let manufacturerData: Data?
    
    /// Service-specific advertisement data.
    public let serviceData: [BluetoothUUID: Data]
    
    /// An array of service UUIDs
    public let serviceUUIDs: [BluetoothUUID]
    
    /// An array of one or more `BluetoothUUID`, representing Service UUIDs that were found
    /// in the “overflow” area of the advertisement data.
    public let overflowServiceUUIDs: [BluetoothUUID]
    
    /// This value is available if the broadcaster (peripheral) provides its Tx power level in its advertising packet.
    /// Using the RSSI value and the Tx power level, it is possible to calculate path loss.
    public let txPowerLevel: Double?
    
    /// A Boolean value that indicates whether the advertising event type is connectable.
    public let isConnectable: Bool?
    
    /// An array of one or more `BluetoothUUID`, representing Service UUIDs.
    public let solicitedServiceUUIDs: [BluetoothUUID]
}

// MARK: - Equatable

extension AdvertisementData: Equatable {
    
    public static func == (lhs: AdvertisementData, rhs: AdvertisementData) -> Bool {
        
        return lhs.localName == rhs.localName
            && lhs.manufacturerData == rhs.manufacturerData
            && lhs.serviceData == rhs.serviceData
            && lhs.serviceUUIDs == rhs.serviceUUIDs
            && lhs.overflowServiceUUIDs == rhs.overflowServiceUUIDs
            && lhs.txPowerLevel == rhs.txPowerLevel
            && lhs.isConnectable == rhs.isConnectable
            && lhs.solicitedServiceUUIDs == rhs.solicitedServiceUUIDs
    }
}

// MARK: - CoreBluetooth

#if os(macOS) || os(iOS) || os(tvOS) || (os(watchOS) && swift(>=3.2))
    
    import Foundation
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
