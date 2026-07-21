//
//  Peripheral.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/1/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

#if BluetoothGATT
@_exported import Bluetooth
@_exported import BluetoothGATT

/// GATT Peripheral Manager
///
/// Implementation varies by operating system.
public protocol PeripheralManager {
    
    /// Central Peer
    ///
    /// Represents a remote central device that has connected to an app implementing the peripheral role on a local device.
    associatedtype Central: Peer
    
    associatedtype Data: DataContainer
    
    associatedtype Error: Swift.Error
    
    var log: (@Sendable (String) -> ())? { get set }
    
    /// Start advertising the peripheral and listening for incoming connections.
    func start() throws(Error)
    
    /// Stop the peripheral.
    func stop()
    
    /// A Boolean value that indicates whether the peripheral is advertising data.
    var isAdvertising: Bool { get }
    
    /// Attempts to add the specified service to the GATT database.
    ///
    /// - Returns: The handle assigned to the service declaration, along with the handles assigned
    ///   to each of its characteristics (and their descriptors), mirroring the structure of `service`.
    func add(service: BluetoothGATT.GATTAttribute<Data>.Service) throws(Error) -> GATTAddedService
    
    /// Removes the service with the specified handle.
    func remove(service: UInt16)
    
    /// Clears the local GATT database.
    func removeAllServices()
    
    /// Callback to handle GATT read requests.
    ///
    /// Return `.success` with the data to serve as the response, overriding the value
    /// stored in the GATT database, or `.failure` to reject the request with the given error.
    var willRead: ((GATTReadRequest<Central, Data>) -> Result<Data, ATTError>)? { get set }
    
    /// Callback to handle GATT write requests.
    var willWrite: ((GATTWriteRequest<Central, Data>) -> ATTError?)? { get set }
    
    /// Callback to handle post-write actions for GATT write requests.
    var didWrite: ((GATTWriteConfirmation<Central, Data>) -> ())? { get set }

    /// Callback to handle when a central connects.
    var didConnect: ((Central) -> ())? { get set }

    /// Callback to handle when a central disconnects.
    var didDisconnect: ((Central) -> ())? { get set }

    /// Modify the value of a characteristic, optionally emiting notifications if configured on active connections.
    func write(_ newValue: Data, forCharacteristic handle: UInt16)
    
    /// Modify the value of a characteristic, optionally emiting notifications if configured on the specified connection.
    ///
    /// Throws error if central is unknown or disconnected.
    func write(_ newValue: Data, forCharacteristic handle: UInt16, for central: Central) throws(Error)
    
    /// Read the value of the characteristic with specified handle.
    subscript(characteristic handle: UInt16) -> Data { get }
    
    /// Read the value of the characteristic with specified handle for the specified connection.
    func value(for characteristicHandle: UInt16, central: Central) throws(Error) -> Data

    /// The negotiated ATT MTU for the specified connected central.
    ///
    /// Throws error if central is unknown or disconnected.
    func maximumTransmissionUnit(for central: Central) throws(Error) -> MaximumTransmissionUnit
}

// MARK: - Supporting Types

/// The handles assigned when adding a service to a peripheral's GATT database.
public struct GATTAddedService: Equatable, Hashable, Sendable {

    /// The handle assigned to the service declaration.
    public let handle: UInt16

    /// The characteristics added for this service, in the same order as the input service.
    public let characteristics: [AddedCharacteristic]

    public init(handle: UInt16, characteristics: [AddedCharacteristic]) {
        self.handle = handle
        self.characteristics = characteristics
    }
}

public extension GATTAddedService {

    /// The handles assigned when adding a characteristic to a peripheral's GATT database.
    struct AddedCharacteristic: Equatable, Hashable, Sendable {

        /// The handle assigned to the characteristic value.
        public let handle: UInt16

        /// The handles assigned to the characteristic's descriptors, in the same order as the input descriptors.
        public let descriptors: [UInt16]

        public init(handle: UInt16, descriptors: [UInt16]) {
            self.handle = handle
            self.descriptors = descriptors
        }
    }
}

public protocol GATTRequest {
    
    associatedtype Central: Peer
    
    associatedtype Data: DataContainer
    
    var central: Central { get }
    
    var maximumUpdateValueLength: Int { get }
    
    var uuid: BluetoothUUID { get }
    
    var handle: UInt16 { get }
    
    var value: Data { get }
}

public struct GATTReadRequest <Central: Peer, Data: DataContainer> : GATTRequest, Equatable, Hashable, Sendable {
    
    public let central: Central
    
    public let maximumUpdateValueLength: Int
    
    public let uuid: BluetoothUUID
    
    public let handle: UInt16
    
    public let value: Data
    
    public let offset: Int
    
    public init(central: Central,
                maximumUpdateValueLength: Int,
                uuid: BluetoothUUID,
                handle: UInt16,
                value: Data,
                offset: Int) {
        
        self.central = central
        self.maximumUpdateValueLength = maximumUpdateValueLength
        self.uuid = uuid
        self.handle = handle
        self.value = value
        self.offset = offset
    }
}

public struct GATTWriteRequest <Central: Peer, Data: DataContainer> : GATTRequest, Equatable, Hashable, Sendable {
    
    public let central: Central
    
    public let maximumUpdateValueLength: Int
    
    public let uuid: BluetoothUUID
    
    public let handle: UInt16
    
    public let value: Data
    
    public let newValue: Data
    
    public init(central: Central,
                maximumUpdateValueLength: Int,
                uuid: BluetoothUUID,
                handle: UInt16,
                value: Data,
                newValue: Data) {
        
        self.central = central
        self.maximumUpdateValueLength = maximumUpdateValueLength
        self.uuid = uuid
        self.handle = handle
        self.value = value
        self.newValue = newValue
    }
}

public struct GATTWriteConfirmation <Central: Peer, Data: DataContainer> : GATTRequest, Equatable, Hashable, Sendable {
    
    public let central: Central
    
    public let maximumUpdateValueLength: Int
    
    public let uuid: BluetoothUUID
    
    public let handle: UInt16
    
    public let value: Data
    
    public init(central: Central,
                maximumUpdateValueLength: Int,
                uuid: BluetoothUUID,
                handle: UInt16,
                value: Data) {
        
        self.central = central
        self.maximumUpdateValueLength = maximumUpdateValueLength
        self.uuid = uuid
        self.handle = handle
        self.value = value
    }
}

#endif
