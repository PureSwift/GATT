//
//  Central.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/3/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import Foundation
import Bluetooth

#if (os(watchOS) && !swift(>=3.2))
// Not supported in watchOS before Xcode 9
public protocol NativeCentral: class { }
#else
/// GATT Central Manager
///
/// Implementation varies by operating system.
public protocol NativeCentral: class {
    
    var log: ((String) -> ())? { get set }
    
    /// Scans for peripherals that are advertising services.
    func scan(filterDuplicates: Bool,
              shouldContinueScanning: () -> (Bool),
              foundDevice: @escaping (ScanData) -> ())
    
    func connect(to peripheral: Peripheral, timeout: TimeInterval) throws
    
    func discoverServices(_ services: [BluetoothUUID],
                          for peripheral: Peripheral,
                          timeout: TimeInterval) throws -> [CentralManager.Service]
    
    func discoverCharacteristics(_ characteristics: [BluetoothUUID],
                                for service: BluetoothUUID,
                                peripheral: Peripheral,
                                timeout: TimeInterval) throws -> [CentralManager.Characteristic]
    
    func readValue(for characteristic: BluetoothUUID,
                   service: BluetoothUUID,
                   peripheral: Peripheral,
                   timeout: TimeInterval) throws -> Data
    
    func writeValue(_ data: Data,
                    for characteristic: BluetoothUUID,
                    withResponse: Bool,
                    service: BluetoothUUID,
                    peripheral: Peripheral,
                    timeout: TimeInterval) throws
    
    func notify(_ notification: ((Data) -> ())?,
                for characteristic: BluetoothUUID,
                service: BluetoothUUID,
                peripheral: Peripheral,
                timeout: TimeInterval) throws
}

public extension NativeCentral {
    
    func scan(duration: TimeInterval, filterDuplicates: Bool = true) -> [ScanData] {
        
        let endDate = Date() + duration
        
        var results = [Peripheral: ScanData]()
        
        self.scan(filterDuplicates: filterDuplicates,
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

#endif
