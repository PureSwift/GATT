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
    func scan(filterDuplicates: Bool,
              shouldContinueScanning: () -> (Bool),
              foundDevice: @escaping (CentralManager.ScanResult) -> ())
    
    func connect(to peripheral: Peripheral, timeout: Int) throws
    
    func discoverServices(for peripheral: Peripheral) throws -> [CentralManager.Service]
    
    func discoverCharacteristics(for service: BluetoothUUID,
                                 peripheral: Peripheral) throws -> [CentralManager.Characteristic]
    
    func read(characteristic uuid: BluetoothUUID,
              service: BluetoothUUID,
              peripheral: Peripheral) throws -> Data
    
    func write(data: Data,
               response: Bool,
               characteristic uuid: BluetoothUUID,
               service: BluetoothUUID,
               peripheral: Peripheral) throws
    
    func notify(characteristic: BluetoothUUID,
                service: BluetoothUUID,
                peripheral: Peripheral,
                notification: ((Data) -> ())?) throws
}

public extension NativeCentral {
    
    func scan(duration: TimeInterval) -> [CentralManager.ScanResult] {
        
        let endDate = Date() + duration
        
        var results = [Peripheral: CentralManager.ScanResult]()
        
        self.scan(filterDuplicates: true,
                  shouldContinueScanning: { Date() < endDate },
                  foundDevice: { results[$0.peripheral] = $0 })
        
        return results.values.sorted(by: { $0.date < $1.date })
    }
}

/// Errors for GATT Central Manager
public enum CentralError: Error {
    
    case timeout
    
    case disconnected
    
    /// Peripheral from previous scan.
    case unknownPeripheral
    
    /// The specified attribute was not found.
    case invalidAttribute(BluetoothUUID)
}

public extension CentralManager {
    
    public struct Service {
        
        public let uuid: BluetoothUUID
        
        public let isPrimary: Bool
    }
    
    public struct Characteristic {
        
        public typealias Property = GATT.CharacteristicProperty
        
        public let uuid: BluetoothUUID
        
        public let properties: BitMaskOptionSet<Property>
    }
}
