//
//  Peripheral.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/1/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import Bluetooth

/// GATT Peripheral Manager Protocol
public protocol PeripheralManager {
    
    /// Attempts to add the specified service to the GATT database.
    func add(service: Service) throws
    
    /// Clears the local GATT database.
    func clear()
    
    
}

// MARK: - Typealiases

public typealias Service = GATT.Service
public typealias Characteristic = GATT.Characteristic
public typealias Descriptor = GATT.Descriptor