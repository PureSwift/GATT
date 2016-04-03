//
//  Peripheral.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/1/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import SwiftFoundation
import Bluetooth

/// GATT Peripheral Manager Interface
public protocol PeripheralManager {
    
    /// Attempts to add the specified service to the GATT database.
    ///
    /// - Returns: Service Index
    func add(service: Service) throws -> Int
    
    /// Removes the service with the specified UUID.
    func remove(service index: Int)
    
    /// Clears the local GATT database.
    func clear()
    
    /// Update the value if the characteristic with specified UUID.
    func update(value: Data, forCharacteristic UUID: Bluetooth.UUID)
    
    /// Start advertising the peripheral and listening for incoming connections.
    func start() throws
    
    /// Stop the peripheral.
    func stop()
    
    var willRead: ((central: Central, UUID: Bluetooth.UUID, value: Data, offset: Int) -> ATT.Error?)? { get }
    
    var willWrite: ((central: Central, UUID: Bluetooth.UUID, value: Data, newValue: (newValue: Data, newBytes: Data, offset: Int)) -> ATT.Error?)? { get }
}

// MARK: - Typealiases

public typealias Service = GATT.Service
public typealias Characteristic = GATT.Characteristic
public typealias Descriptor = GATT.Descriptor