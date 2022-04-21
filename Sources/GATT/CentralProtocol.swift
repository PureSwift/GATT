//
//  Central.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/3/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

#if swift(>=5.5)
import Foundation
import Bluetooth

/// GATT Central Manager
///
/// Implementation varies by operating system and framework.
@available(macOS 10.5, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public protocol CentralManager: AnyObject {
    
    /// Central Peripheral Type
    associatedtype Peripheral: Peer
    
    /// Central Advertisement Type
    associatedtype Advertisement: AdvertisementData
    
    /// Central Attribute ID (Handle)
    associatedtype AttributeID: Hashable
    
    /// Logging
    var log: ((String) -> ())? { get set }
    
    /// Currently scanned devices, or restored devices.
    var peripherals: Set<Peripheral> { get async }
    
    /// Scans for peripherals that are advertising services.
    func scan(filterDuplicates: Bool) async throws -> AsyncCentralScan<Self>
    
    /// Disconnected peripheral callback
    //var didDisconnect: AsyncStream<Peripheral> { get }
    
    /// Connect to the specified device
    func connect(to peripheral: Peripheral) async throws
    
    /// Disconnect the specified device.
    func disconnect(_ peripheral: Peripheral) async
    
    /// Disconnect all connected devices.
    func disconnectAll() async
    
    /// Discover Services
    func discoverServices(
        _ services: Set<BluetoothUUID>,
        for peripheral: Peripheral
    ) async throws -> [Service<Peripheral, AttributeID>]
    
    /// Discover Characteristics for service
    func discoverCharacteristics(
        _ characteristics: Set<BluetoothUUID>,
        for service: Service<Peripheral, AttributeID>
    ) async throws -> [Characteristic<Peripheral, AttributeID>]
    
    /// Read Characteristic Value
    func readValue(
        for characteristic: Characteristic<Peripheral, AttributeID>
    ) async throws -> Data
    
    /// Write Characteristic Value
    func writeValue(
        _ data: Data,
        for characteristic: Characteristic<Peripheral, AttributeID>,
        withResponse: Bool
    ) async throws
    
    /// Discover descriptors
    func discoverDescriptors(
        for characteristic: Characteristic<Peripheral, AttributeID>
    ) async throws -> [Descriptor<Peripheral, AttributeID>]
    
    /// Read descriptor
    func readValue(
        for descriptor: Descriptor<Peripheral, AttributeID>
    ) async throws -> Data
    
    /// Write descriptor
    func writeValue(
        _ data: Data,
        for descriptor: Descriptor<Peripheral, AttributeID>
    ) async throws
    
    /// Start Notifications
    func notify(
        for characteristic: Characteristic<Peripheral, AttributeID>
    ) async throws -> AsyncCentralNotifications<Self>
    
    /// Read MTU
    func maximumTransmissionUnit(for peripheral: Peripheral) async throws -> MaximumTransmissionUnit
    
    // Read RSSI
    func rssi(for peripheral: Peripheral) async throws -> RSSI
}

#endif
