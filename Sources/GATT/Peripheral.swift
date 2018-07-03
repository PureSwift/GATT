//
//  Peripheral.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/1/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import Foundation
import Bluetooth

/// GATT Peripheral Manager
///
/// Implementation varies by operating system.
public protocol PeripheralProtocol: class {
    
    /// Start advertising the peripheral and listening for incoming connections.
    func start() throws
    
    /// Stop the peripheral.
    func stop()
    
    /// The closure to call for logging.
    var log: ((String) -> ())? { get }
    
    /// Attempts to add the specified service to the GATT database.
    ///
    /// - Returns: Attribute handle.
    func add(service: GATT.Service) throws -> UInt16
    
    /// Removes the service with the specified handle.
    func remove(service: UInt16)
    
    /// Clears the local GATT database.
    func removeAllServices()
    
    var willRead: ((GATTReadRequest) -> ATT.Error?)? { get set }
    
    var willWrite: ((GATTWriteRequest) -> ATT.Error?)? { get set }
    
    var didWrite: ((GATTWriteConfirmation) -> ())? { get set }
    
    /// Write / Read the value of the characteristic with specified handle.
    subscript(characteristic handle: UInt16) -> Data { get set }
    
    /// Return the handles of the characteristics matching the specified UUID.
    func characteristics(for uuid: BluetoothUUID) -> [UInt16]
}

// MARK: - Supporting Types

public protocol GATTRequest {
    
    var central: Central { get }
    
    var maximumUpdateValueLength: Int { get }
    
    var uuid: BluetoothUUID { get }
    
    var handle: UInt16 { get }
    
    var value: Data { get }
}

public struct GATTReadRequest: GATTRequest {
    
    public let central: Central
    
    public let maximumUpdateValueLength: Int
    
    public let uuid: BluetoothUUID
    
    public let handle: UInt16
    
    public let value: Data
    
    public let offset: Int
}

public struct GATTWriteRequest: GATTRequest {
    
    public let central: Central
    
    public let maximumUpdateValueLength: Int
    
    public let uuid: BluetoothUUID
    
    public let handle: UInt16
    
    public let value: Data
    
    public let newValue: Data
}

public struct GATTWriteConfirmation: GATTRequest {
    
    public let central: Central
    
    public let maximumUpdateValueLength: Int
    
    public let uuid: BluetoothUUID
    
    public let handle: UInt16
    
    public let value: Data
}
