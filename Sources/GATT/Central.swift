//
//  Central.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/3/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import SwiftFoundation
import Bluetooth

/// GATT Central Manager
///
/// Implementation varies by operating system.
public protocol NativeCentral {
    
    var log: (String -> ())? { get set }
    
    func scan(duration: Int) -> [Peripheral]
    
    func connect(peripheral: Peripheral, timeout: Int) throws
    
    func discover(services peripheral: Peripheral) throws -> [(UUID: Bluetooth.UUID, primary: Bool)]
    
    func discover(characteristics service: Bluetooth.UUID, peripheral: Peripheral) throws -> [(UUID: Bluetooth.UUID, properties: [Characteristic.Property])]
    
    func read(characteristic UUID: Bluetooth.UUID, service: Bluetooth.UUID, peripheral: Peripheral) throws -> Data
}

/// Errors for GATT Central Manager
public enum CentralError: ErrorProtocol {
    
    case Timeout
}