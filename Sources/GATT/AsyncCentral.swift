//
//  AsyncCentral.swift
//  
//
//  Created by Alsey Coleman Miller on 11/10/21.
//

#if swift(>=5.5)
import Foundation
import Bluetooth

@available(macOS 12, iOS 15.0, watchOS 8.0, tvOS 15, *)
public protocol AsyncCentral {
    
    /// Central Peripheral Type
    associatedtype Peripheral: Peer
    
    /// Central Advertisement Type
    associatedtype Advertisement: AdvertisementData
    
    /// Central Attribute ID (Handle)
    associatedtype AttributeID: Hashable
    
    /// Log stream
    var log: AsyncStream<String> { get }
    
    /// Scans for peripherals that are advertising services.
    func scan(filterDuplicates: Bool) -> AsyncThrowingStream<ScanData<Peripheral, Advertisement>, Error>
    
    /// Stops scanning for peripherals.
    func stopScan() async
    
    /// Scanning status
    var isScanning: AsyncStream<Bool> { get }
    
    /// Connect to the specified device
    func connect(to peripheral: Peripheral) async throws
    
    /// Disconnect the specified device.
    func disconnect(_ peripheral: Peripheral) async
    
    /// Disconnect all connected devices.
    func disconnectAll() async
    
    /// Disconnected peripheral callback
    var didDisconnect: AsyncStream<Peripheral> { get }
    
    /// Discover Services
    func discoverServices(
        _ services: [BluetoothUUID],
        for peripheral: Peripheral
    ) -> AsyncThrowingStream<Service<Peripheral, AttributeID>, Error>
    
    /// Discover Characteristics for service
    func discoverCharacteristics(
        _ characteristics: [BluetoothUUID],
        for service: Service<Peripheral, AttributeID>
    ) -> AsyncThrowingStream<Characteristic<Peripheral, AttributeID>, Error>
    
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
    
    /// Start Notifications
    func notify(
        for characteristic: Characteristic<Peripheral, AttributeID>
    ) -> AsyncThrowingStream<Data, Error>
    
    // Stop Notifications
    func stopNotifications(for characteristic: Characteristic<Peripheral, AttributeID>) async throws
    
    /// Read MTU
    func maximumTransmissionUnit(for peripheral: Peripheral) async throws -> MaximumTransmissionUnit
    
    // Read RSSI
    func rssi(for peripheral: Peripheral) async throws -> RSSI
}

#endif
