//
//  AdvertisementData.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 3/9/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

@_exported import Bluetooth

/// GATT Advertisement Data.
public protocol AdvertisementData: Hashable, Sendable {
    
    associatedtype Data where Data: DataContainer
    
    /// The local name of a peripheral.
    var localName: String? { get }
    
    /// The Manufacturer data of a peripheral.
    var manufacturerData: ManufacturerSpecificData<Data>? { get }
    
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

extension LowEnergyAdvertisingData: AdvertisementData {
    
    public typealias Data = Self
    
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
    public var manufacturerData: GAPManufacturerSpecificData<Self>? {
        
        guard let value = try? GAPDataDecoder.decode(GAPManufacturerSpecificData<Self>.self, from: self)
            else { return nil }
        
        return ManufacturerSpecificData(
            companyIdentifier: value.companyIdentifier,
            additionalData: value.additionalData
        )
    }
    
    /// Service-specific advertisement data.
    public var serviceData: [BluetoothUUID: Self]? {
        
        var serviceData = [BluetoothUUID: Self](minimumCapacity: 3)
        
        if let value = try? GAPDataDecoder.decode(GAPServiceData16BitUUID<Self>.self, from: self) {
            serviceData[.bit16(value.uuid)] = value.serviceData
        }
        if let value = try? GAPDataDecoder.decode(GAPServiceData32BitUUID<Self>.self, from: self) {
            serviceData[.bit32(value.uuid)] = value.serviceData
        }
        if let value = try? GAPDataDecoder.decode(GAPServiceData128BitUUID<Self>.self, from: self) {
            serviceData[.bit128(UInt128(uuid: value.uuid))] = value.serviceData
        }
        
        guard serviceData.isEmpty == false
            else { return nil }
        
        return serviceData
    }
    
    /// An array of service UUIDs
    public var serviceUUIDs: [BluetoothUUID]? {
        
        var uuids = [BluetoothUUID]()
        uuids.reserveCapacity(2)
        
        if let value = try? GAPDataDecoder.decode(GAPCompleteListOf16BitServiceClassUUIDs.self, from: self) {
            uuids += value.uuids.map { .bit16($0) }
        }
        if let value = try? GAPDataDecoder.decode(GAPIncompleteListOf16BitServiceClassUUIDs.self, from: self) {
            uuids += value.uuids.map { .bit16($0) }
        }
        if let value = try? GAPDataDecoder.decode(GAPIncompleteListOf32BitServiceClassUUIDs.self, from: self) {
            uuids += value.uuids.map { .bit32($0) }
        }
        if let value = try? GAPDataDecoder.decode(GAPIncompleteListOf32BitServiceClassUUIDs.self, from: self) {
            uuids += value.uuids.map { .bit32($0) }
        }
        if let value = try? GAPDataDecoder.decode(GAPCompleteListOf128BitServiceClassUUIDs.self, from: self) {
            uuids += value.uuids.map { .init(uuid: $0) }
        }
        if let value = try? GAPDataDecoder.decode(GAPIncompleteListOf128BitServiceClassUUIDs.self, from: self) {
            uuids += value.uuids.map { .init(uuid: $0) }
        }
        
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
        
        var uuids = [BluetoothUUID]()
        uuids.reserveCapacity(2)
        
        if let value = try? GAPDataDecoder.decode(GAPListOf16BitServiceSolicitationUUIDs.self, from: self) {
            uuids += value.uuids.map { .bit16($0) }
        }
        if let value = try? GAPDataDecoder.decode(GAPListOf32BitServiceSolicitationUUIDs.self, from: self) {
            uuids += value.uuids.map { .bit32($0) }
        }
        if let value = try? GAPDataDecoder.decode(GAPListOf128BitServiceSolicitationUUIDs.self, from: self) {
            uuids += value.uuids.map { .init(uuid: $0) }
        }
        
        guard uuids.isEmpty == false
            else { return nil }
        
        return uuids
    }
}

#endif
