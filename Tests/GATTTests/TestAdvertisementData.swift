//
//  TestAdvertisementData.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 7/16/18.
//
//

import Foundation
import Bluetooth
import GATT

public struct TestAdvertisementData: AdvertisementData {
    
    public let data: Data
    
    internal init(data: Data) {
        
        self.data = data
    }
}

extension TestAdvertisementData: Equatable {
    
    public static func == (lhs: TestAdvertisementData, rhs: TestAdvertisementData) -> Bool {
        
        return lhs.data == rhs.data
    }
}

// MARK: - Accessors

public extension TestAdvertisementData {
    
    /// The local name of a peripheral.
    public var localName: String? {
        
        let types: [GAPData.Type] = [
            GAPCompleteLocalName.self,
            GAPShortLocalName.self
        ]
        
        guard let decoded = try? GAPDataDecoder.decode(data, types: types, ignoreUnknownType: true)
            else { return nil }
        
        let completeNames = decoded.flatMap { $0 as? GAPCompleteLocalName }
        let shortNames = decoded.flatMap { $0 as? GAPShortLocalName }
        
        return completeNames.first?.name ?? shortNames.first?.name
    }
    
    /// The Manufacturer data of a peripheral.
    public var manufacturerData: Data? {
        
        return (try? GAPDataDecoder.decode(data, types: [GAPManufacturerSpecificData.self], ignoreUnknownType: true))?
            .flatMap { $0 as? GAPManufacturerSpecificData }
            .first?.data
    }
    
    /// Service-specific advertisement data.
    public var serviceData: [BluetoothUUID: Data] {
        
        return [:]
    }
    
    /// An array of service UUIDs
    public var serviceUUIDs: [BluetoothUUID] {
        
        return []
    }
    
    /// An array of one or more `BluetoothUUID`, representing Service UUIDs that were found
    /// in the “overflow” area of the advertisement data.
    public var overflowServiceUUIDs: [BluetoothUUID] {
        
        return []
    }
    
    /// This value is available if the broadcaster (peripheral) provides its Tx power level in its advertising packet.
    /// Using the RSSI value and the Tx power level, it is possible to calculate path loss.
    public var txPowerLevel: Double? {
        
        guard let gapData = (try? GAPDataDecoder.decode(data, types: [GAPManufacturerSpecificData.self], ignoreUnknownType: true))?.first as? GAPTxPowerLevel else { return nil }
        
        return Double(gapData.powerLevel)
    }
    
    /// A Boolean value that indicates whether the advertising event type is connectable.
    public var isConnectable: Bool? {
        
        return (try? GAPDataDecoder.decode(data, types: [GAPManufacturerSpecificData.self], ignoreUnknownType: true))?
            .flatMap { $0 as? GAPFlags }
            .first?.flags.contains(.lowEnergyGeneralDiscoverableMode)
    }
    
    /// An array of one or more `BluetoothUUID`, representing Service UUIDs.
    public var solicitedServiceUUIDs: [BluetoothUUID] {
        
        return []
    }
}
