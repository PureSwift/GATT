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
public protocol NativePeripheral {
    
    associatedtype ServiceIdentifier
    
    /// Start advertising the peripheral and listening for incoming connections.
    func start() throws
    
    /// Stop the peripheral.
    func stop()
    
    /// The closure to call for logging.
    var log: ((String) -> ())? { get }
    
    /// Attempts to add the specified service to the GATT database.
    ///
    /// - Returns: Service Index
    func add(service: GATT.Service) throws -> ServiceIdentifier
    
    /// Removes the service with the specified UUID.
    func remove(service: ServiceIdentifier)
    
    /// Clears the local GATT database.
    func clear()
    
    var willRead: ((_ central: Central, _ UUID: BluetoothUUID, _ value: Data, _ offset: Int) -> ATT.Error?)? { get set }
    
    var willWrite: ((_ central: Central, _ UUID: BluetoothUUID, _ value: Data, _ newValue: Data) -> ATT.Error?)? { get set }
    
    var didWrite: ((_ central: Central, _ UUID: BluetoothUUID, _ value: Data, _ newValue: Data) -> ())? { get set }
    
    /// Write / Read the value of the characteristic with specified UUID.
    subscript(characteristic uuid: BluetoothUUID) -> Data { get set }
}
