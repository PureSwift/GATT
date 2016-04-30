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
    
#if os(iOS) || os(Linux) || XcodeLinux
    
    /// Start advertising the peripheral and listening for incoming connections.
    ///
    /// - Note: Can optionally advertise as iBeacon in iOS and Linux.
    func start(beacon: Beacon?) throws
    
#elseif os(OSX)
    
    /// Start advertising the peripheral and listening for incoming connections.
    func start() throws

#endif
    
    /// Stop the peripheral.
    func stop()
    
    /// The closure to call for internal logging.
    var log: (String -> ())? { get }
    
    /// Attempts to add the specified service to the GATT database.
    ///
    /// - Returns: Service Index
    func add(service: Service) throws -> ServiceIdentifier
    
    /// Removes the service with the specified UUID.
    func remove(service: ServiceIdentifier)
    
    /// Clears the local GATT database.
    func clear()
    
    var willRead: ((central: Central, UUID: Bluetooth.UUID, value: Data, offset: Int) -> ATT.Error?)? { get set }
    
    var willWrite: ((central: Central, UUID: Bluetooth.UUID, value: Data, newValue: Data) -> ATT.Error?)? { get set }
    
    var didWrite: ((central: Central, UUID: Bluetooth.UUID, value: Data, newValue: Data) -> ())? { get set }
    
    /// Write / Read the value of the characteristic with specified UUID.
    subscript(characteristic UUID: Bluetooth.UUID) -> Data { get set }
}

// MARK: - Typealiases

public typealias Service = GATT.Service
public typealias Characteristic = GATT.Characteristic
public typealias Descriptor = GATT.Descriptor
