//
//  Central.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/3/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import Foundation
import Bluetooth

/// GATT Central Manager
///
/// Implementation varies by operating system.
public protocol NativeCentral: class {
    
    var log: ((String) -> ())? { get set }
    
    /// Scans for peripherals that are advertising services.
    func scan(duration: Int) -> [ScanResult]
    
    func connect(to peripheral: Peripheral, timeout: Int) throws
    
    func discoverServices(for peripheral: Peripheral) throws -> [(uuid: BluetoothUUID, primary: Bool)]
    
    func discoverCharacteristics(for service: BluetoothUUID,
                                 peripheral: Peripheral) throws -> [(uuid: BluetoothUUID, properties: [Characteristic.Property])]
    
    func read(characteristic uuid: BluetoothUUID,
              service: BluetoothUUID,
              peripheral: Peripheral) throws -> Data
    
    func write(data: Data,
               response: Bool,
               characteristic uuid: BluetoothUUID,
               service: BluetoothUUID,
               peripheral: Peripheral) throws
    
    func notify(_ notification: ((Data) -> ())?,
                for characteristic: BluetoothUUID,
                service: BluetoothUUID,
                peripheral: Peripheral) throws
}

/// Errors for GATT Central Manager
public enum CentralError: Error {
    
    case timeout
    
    case disconnected
    
    /// Peripheral from previous scan.
    case unknownPeripheral
}
