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
    
    /// Default initializer
    init()
    
    func add(service: GATT.Service)
    
    func remove(service: GATT.Service)
}