//
//  AdvertisementData.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 3/9/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
@_exported import Bluetooth

/// GATT Advertisement Data.
public protocol AdvertisementData: Hashable {
    
    /// The local name of a peripheral.
    var localName: String? { get }
    
    /// The Manufacturer data of a peripheral.
    var manufacturerData: ManufacturerSpecificData? { get }
    
    /// This value is available if the broadcaster (peripheral) provides its Tx power level in its advertising packet.
    /// Using the RSSI value and the Tx power level, it is possible to calculate path loss.
    var txPowerLevel: Double? { get }
    
    /// Service-specific advertisement data.
    var serviceData: [BluetoothUUID: Data]? { get }
    
    /// An array of service UUIDs
    var serviceUUIDs: [BluetoothUUID]? { get }
    
    /// An array of one or more `BluetoothUUID`, representing Service UUIDs.
    var solicitedServiceUUIDs: [BluetoothUUID]? { get }
}

#if canImport(BluetoothGAP)
import BluetoothGAP

// MARK: - LowEnergyAdvertisingData

extension LowEnergyAdvertisingData: GATT.AdvertisementData {
    
    /// Decode GAP data types.
    private func decode() -> [GAPData] {
        
        var decoder = GAPDataDecoder()
        decoder.ignoreUnknownType = true
        return (try? decoder.decode(self)) ?? []
    }
    
    /// The local name of a peripheral.
    public var localName: String? {
        
        if let decoded = try? GAPDataDecoder.decode(GAPCompleteLocalName.self, from: self) {
            return decoded.name
        } else if let decoded = try? GAPDataDecoder.decode(GAPShortLocalName.self, from: self) {
            return decoded.name
        } else {
            return nil
        }
    }
    
    /// The Manufacturer data of a peripheral.
    public var manufacturerData: ManufacturerSpecificData? {
        
        guard let value = try? GAPDataDecoder.decode(GAPManufacturerSpecificData.self, from: self)
            else { return nil }
        
        return ManufacturerSpecificData(
            companyIdentifier: value.companyIdentifier,
            additionalData: value.additionalData
        )
    }
    
    /// Service-specific advertisement data.
    public var serviceData: [BluetoothUUID: Data]? {
        
        let decoded = decode()
        
        guard decoded.isEmpty == false
            else { return nil }
        
        var serviceData = [BluetoothUUID: Data](minimumCapacity: decoded.count)
        
        decoded.compactMap { $0 as? GAPServiceData16BitUUID }
            .forEach { serviceData[.bit16($0.uuid)] = $0.serviceData }
        
        decoded.compactMap { $0 as? GAPServiceData32BitUUID }
            .forEach { serviceData[.bit32($0.uuid)] = $0.serviceData }
        
        decoded.compactMap { $0 as? GAPServiceData128BitUUID }
            .forEach { serviceData[.bit128(UInt128(uuid: $0.uuid))] = $0.serviceData }
        
        guard serviceData.isEmpty == false
            else { return nil }
        
        return serviceData
    }
    
    /// An array of service UUIDs
    public var serviceUUIDs: [BluetoothUUID]? {
        
        let decoded = decode()
        
        guard decoded.isEmpty == false
            else { return nil }
        
        var uuids = [BluetoothUUID]()
        uuids.reserveCapacity(decoded.count)
        
        uuids += decoded
            .compactMap { $0 as? GAPCompleteListOf16BitServiceClassUUIDs }
            .reduce([BluetoothUUID](), { $0 + $1.uuids.map { BluetoothUUID.bit16($0) } })
        
        uuids += decoded
            .compactMap { $0 as? GAPIncompleteListOf16BitServiceClassUUIDs }
            .reduce([BluetoothUUID](), { $0 + $1.uuids.map { BluetoothUUID.bit16($0) } })
        
        uuids += decoded
            .compactMap { $0 as? GAPCompleteListOf32BitServiceClassUUIDs }
            .reduce([BluetoothUUID](), { $0 + $1.uuids.map { BluetoothUUID.bit32($0) } })
        
        uuids += decoded
            .compactMap { $0 as? GAPIncompleteListOf32BitServiceClassUUIDs }
            .reduce([BluetoothUUID](), { $0 + $1.uuids.map { BluetoothUUID.bit32($0) } })
        
        uuids += decoded
            .compactMap { $0 as? GAPCompleteListOf128BitServiceClassUUIDs }
            .reduce([BluetoothUUID](), { $0 + $1.uuids.map { BluetoothUUID(uuid: $0) } })
        
        uuids += decoded
            .compactMap { $0 as? GAPIncompleteListOf128BitServiceClassUUIDs }
            .reduce([BluetoothUUID](), { $0 + $1.uuids.map { BluetoothUUID(uuid: $0) } })
        
        guard uuids.isEmpty == false
            else { return nil }
        
        return uuids
    }
    
    /// This value is available if the broadcaster (peripheral) provides its Tx power level in its advertising packet.
    /// Using the RSSI value and the Tx power level, it is possible to calculate path loss.
    public var txPowerLevel: Double? {
        
        guard let value = try? GAPDataDecoder.decode(GAPTxPowerLevel.self, from: self)
            else { return nil }
        
        return Double(value.powerLevel)
    }
    
    /// An array of one or more `BluetoothUUID`, representing Service UUIDs.
    public var solicitedServiceUUIDs: [BluetoothUUID]? {
        
        let decoded = decode()
        
        guard decoded.isEmpty == false
            else { return nil }
        
        var uuids = [BluetoothUUID]()
        uuids.reserveCapacity(decoded.count)
        
        decoded.compactMap { $0 as? GAPListOf16BitServiceSolicitationUUIDs }
            .forEach { $0.uuids.forEach { uuids.append(.bit16($0)) } }
        
        decoded.compactMap { $0 as? GAPListOf32BitServiceSolicitationUUIDs }
            .forEach { $0.uuids.forEach { uuids.append(.bit32($0)) } }
        
        decoded.compactMap { $0 as? GAPListOf128BitServiceSolicitationUUIDs }
            .forEach { $0.uuids.forEach { uuids.append(.bit128(UInt128(uuid: $0))) } }
        
        guard uuids.isEmpty == false
            else { return nil }
        
        return uuids
    }
}

#endif
