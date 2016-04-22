//
//  Peripheral.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/1/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import SwiftFoundation
import Bluetooth

/// GATT Peripheral Manager
///
/// Implementation varies by operating system.
public protocol NativePeripheral {
    
    associatedtype ServiceIdentifier
    
    var log: (String -> ())? { get }
    
    /// Attempts to add the specified service to the GATT database.
    ///
    /// - Returns: Service Index
    func add(service: Service) throws -> ServiceIdentifier
    
    /// Removes the service with the specified UUID.
    func remove(service: ServiceIdentifier)
    
    /// Clears the local GATT database.
    func clear()
    
    /// Start advertising the peripheral and listening for incoming connections.
    func start() throws
    
    /// Stop the peripheral.
    func stop()
    
    var willRead: ((central: Central, UUID: Bluetooth.UUID, value: Data, offset: Int) -> ATT.Error?)? { get }
    
    var willWrite: ((central: Central, UUID: Bluetooth.UUID, value: Data, newValue: Data) -> ATT.Error?)? { get }
    
    /// Write / Read the value of the characteristic with specified UUID.
    subscript(characteristic UUID: Bluetooth.UUID) -> Data { get set }
}

// MARK: - Typealiases

public typealias Service = GATT.Service
public typealias Characteristic = GATT.Characteristic
public typealias Descriptor = GATT.Descriptor
