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
    func clear()
    
    var willRead: ((_ central: Central, _ uuid: BluetoothUUID, _ handle: UInt16, _ value: Data, _ offset: Int) -> ATT.Error?)? { get set }
    
    var willWrite: ((_ central: Central, _ uuid: BluetoothUUID, _ handle: UInt16, _ value: Data, _ newValue: Data) -> ATT.Error?)? { get set }
    
    var didWrite: ((_ central: Central, _ uuid: BluetoothUUID, _ handle: UInt16, _ value: Data, _ newValue: Data) -> ())? { get set }
    
    /// Write / Read the value of the characteristic with specified handle.
    subscript(characteristic handle: UInt16) -> Data { get set }
    
    /// Get the UUID of the service or characteristic for the specified attribute.
    //func uuid(for handle: AttributeHandle) -> BluetoothUUID
    
    /// Get the handles associated with the specified UUID.
    //func handles(for uuid: BluetoothUUID) -> AttributeHandle
}
