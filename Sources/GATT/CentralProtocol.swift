//
//  Central.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/3/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

#if !EMBEDDED_NO_CONCURRENCY

#if hasFeature(Embedded)
// Embedded Swift does not import the concurrency module implicitly.
import _Concurrency
#endif
import Bluetooth

/// GATT Central Manager
///
/// Implementation varies by operating system and framework.
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public protocol CentralManager: AnyObject {
    
    /// Central Peripheral Type
    associatedtype Peripheral: Peer
    
    /// Central Advertisement Type
    associatedtype Advertisement: AdvertisementData
    
    /// Central Attribute ID (Handle)
    associatedtype AttributeID: Hashable
    
    associatedtype Data: DataContainer

    /// The error the central's operations throw.
    ///
    /// A conformer whose methods use untyped `throws` gets `any Error` without
    /// naming it. Embedded Swift has no `any Error`, so a conformer built for it
    /// names a concrete error type.
    ///
    /// A conformer that implements some requirements without `throws` declares
    /// `typealias Failure = any Error`: otherwise Swift can't tell whether it
    /// meant `Never` or `any Error`.
    associatedtype Failure: Error

    /// Logging
    var log: (@Sendable (String) -> ())? { get set }
    
    /// Currently scanned devices, or restored devices.
    var peripherals: [Peripheral: Bool] { get async }
    
    /// Scans for peripherals that are advertising services.
    func scan(filterDuplicates: Bool) async throws(Failure) -> AsyncCentralScan<Self>
    
    /// Disconnected peripheral callback
    //var didDisconnect: AsyncStream<Peripheral> { get }
    
    /// Connect to the specified device
    func connect(to peripheral: Peripheral) async throws(Failure)
    
    /// Disconnect the specified device.
    func disconnect(_ peripheral: Peripheral) async
    
    /// Disconnect all connected devices.
    func disconnectAll() async
    
    /// Discover Services
    func discoverServices(
        _ services: Set<BluetoothUUID>,
        for peripheral: Peripheral
    ) async throws(Failure) -> [Service<Peripheral, AttributeID>]
    
    /// Discover Characteristics for service
    func discoverCharacteristics(
        _ characteristics: Set<BluetoothUUID>,
        for service: Service<Peripheral, AttributeID>
    ) async throws(Failure) -> [Characteristic<Peripheral, AttributeID>]
    
    /// Read Characteristic Value
    func readValue(
        for characteristic: Characteristic<Peripheral, AttributeID>
    ) async throws(Failure) -> Data
    
    /// Write Characteristic Value
    func writeValue(
        _ data: Data,
        for characteristic: Characteristic<Peripheral, AttributeID>,
        withResponse: Bool
    ) async throws(Failure)
    
    /// Discover descriptors
    func discoverDescriptors(
        for characteristic: Characteristic<Peripheral, AttributeID>
    ) async throws(Failure) -> [Descriptor<Peripheral, AttributeID>]
    
    /// Read descriptor
    func readValue(
        for descriptor: Descriptor<Peripheral, AttributeID>
    ) async throws(Failure) -> Data
    
    /// Write descriptor
    func writeValue(
        _ data: Data,
        for descriptor: Descriptor<Peripheral, AttributeID>
    ) async throws(Failure)
    
    /// Start Notifications
    func notify(
        for characteristic: Characteristic<Peripheral, AttributeID>
    ) async throws(Failure) -> AsyncCentralNotifications<Self>
    
    /// Read MTU
    func maximumTransmissionUnit(for peripheral: Peripheral) async throws(Failure) -> MaximumTransmissionUnit
    
    // Read RSSI
    func rssi(for peripheral: Peripheral) async throws(Failure) -> RSSI
}

#endif
