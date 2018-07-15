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
    
    public init(localName: String? = nil,
                manufacturerData: Data? = nil,
                serviceData: [BluetoothUUID: Data] = [:],
                serviceUUIDs: [BluetoothUUID] = [],
                overflowServiceUUIDs: [BluetoothUUID] = [],
                txPowerLevel: Double? = nil,
                isConnectable: Bool? = nil,
                solicitedServiceUUIDs: [BluetoothUUID] = []) {
        
        self.localName = localName
        self.manufacturerData = manufacturerData
        self.serviceData = serviceData
        self.serviceUUIDs = serviceUUIDs
        self.overflowServiceUUIDs = overflowServiceUUIDs
        self.txPowerLevel = txPowerLevel
        self.isConnectable = isConnectable
        self.solicitedServiceUUIDs = solicitedServiceUUIDs
    }
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
