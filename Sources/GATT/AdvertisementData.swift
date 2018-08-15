//
//  AdvertisementData.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 3/9/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import Bluetooth

/// GATT Advertisement Data.
public protocol AdvertisementDataProtocol: Equatable {
    
    /// The local name of a peripheral.
    var localName: String? { get }
    
    /// The Manufacturer data of a peripheral.
    var manufacturerData: Data? { get }
    
    /// A Boolean value that indicates whether the advertising event type is connectable.
    var isConnectable: Bool? { get }
    
    /// This value is available if the broadcaster (peripheral) provides its Tx power level in its advertising packet.
    /// Using the RSSI value and the Tx power level, it is possible to calculate path loss.
    var txPowerLevel: Double? { get }
    
    /// Service-specific advertisement data.
    var serviceData: [BluetoothUUID: Data] { get }
    
    /// An array of service UUIDs
    var serviceUUIDs: [BluetoothUUID] { get }
    
    /// An array of one or more `BluetoothUUID`, representing Service UUIDs.
    var solicitedServiceUUIDs: [BluetoothUUID] { get }
}


public struct AdvertisementData: AdvertisementDataProtocol {
    
    public let advertisement: LowEnergyAdvertisingData
    
    public var scanResponse: LowEnergyAdvertisingData?
    
    public init(advertisement: LowEnergyAdvertisingData,
                scanResponse: LowEnergyAdvertisingData? = nil) {
        
        self.advertisement = advertisement
        self.scanResponse = scanResponse
    }
}

extension AdvertisementData: Equatable {
    
    public static func == (lhs: AdvertisementData, rhs: AdvertisementData) -> Bool {
        
        return lhs.advertisment == rhs.advertisment
            && lhs.scanResponse == rhs.scanResponse
    }
}

// MARK: - Accessors

public extension AdvertisementData {
    
    /// The local name of a peripheral.
    public var localName: String? {
        
        let types: [GAPData.Type] = [
            GAPCompleteLocalName.self,
            GAPShortLocalName.self
        ]
        
        for data in [advertisment, scanResponse].flatMap({ $0?.data }) {
            
            guard let decoded = try? GAPDataDecoder.decode(data, types: types, ignoreUnknownType: true)
                else { continue }
            
            guard let name = decoded.flatMap({ $0 as? GAPCompleteLocalName }).first?.name
                ?? decoded.flatMap({ $0 as? GAPShortLocalName }).first?.name
                else { continue }
            
            return name
        }
        
        // not found
        return nil
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
        
        let types: [GAPData.Type] = [
            GAPCompleteListOf16BitServiceClassUUIDs.self,
            GAPIncompleteListOf16BitServiceClassUUIDs.self,
            GAPCompleteListOf32BitServiceClassUUIDs.self,
            GAPIncompleteListOf32BitServiceClassUUIDs.self,
            GAPCompleteListOf128BitServiceClassUUIDs.self,
            GAPIncompleteListOf128BitServiceClassUUIDs.self
        ]
        
        guard let decoded = try? GAPDataDecoder.decode(data, types: types, ignoreUnknownType: true),
            decoded.isEmpty == false
            else { return [] }
        
        var uuids = [BluetoothUUID]()
        
        uuids += decoded
            .flatMap { $0 as? GAPCompleteListOf16BitServiceClassUUIDs }
            .reduce([BluetoothUUID](), { $0.0 + $0.1.uuids.map { BluetoothUUID.bit16($0) } })
        
        uuids += decoded
            .flatMap { $0 as? GAPIncompleteListOf16BitServiceClassUUIDs }
            .reduce([BluetoothUUID](), { $0.0 + $0.1.uuids.map { BluetoothUUID.bit16($0) } })
        
        uuids += decoded
            .flatMap { $0 as? GAPCompleteListOf32BitServiceClassUUIDs }
            .reduce([BluetoothUUID](), { $0.0 + $0.1.uuids.map { BluetoothUUID.bit32($0) } })
        
        uuids += decoded
            .flatMap { $0 as? GAPIncompleteListOf32BitServiceClassUUIDs }
            .reduce([BluetoothUUID](), { $0.0 + $0.1.uuids.map { BluetoothUUID.bit32($0) } })
        
        uuids += decoded
            .flatMap { $0 as? GAPCompleteListOf128BitServiceClassUUIDs }
            .reduce([BluetoothUUID](), { $0.0 + $0.1.uuids.map { BluetoothUUID(uuid: $0) } })
        
        uuids += decoded
            .flatMap { $0 as? GAPIncompleteListOf128BitServiceClassUUIDs }
            .reduce([BluetoothUUID](), { $0.0 + $0.1.uuids.map { BluetoothUUID(uuid: $0) } })
        
        return uuids
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
