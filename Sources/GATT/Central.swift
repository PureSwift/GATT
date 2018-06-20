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

/// Errors for GATT Central Manager
public enum CentralError: Error {
    
    /// Operation timeout.
    case timeout
    
    /// Peripheral is disconnected.
    case disconnected(Peripheral)
    
    /// Peripheral from previous scan / unknown.
    case unknownPeripheral(Peripheral)
    
    /// The specified attribute was not found.
    case invalidAttribute(BluetoothUUID)
}

// MARK: - CustomNSError

#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)

import Foundation

extension CentralError: CustomNSError {
    
    public enum UserInfoKey: String {
        
        /// Bluetooth UUID value (for characteristic or service).
        case uuid = "org.pureswift.GATT.CentralError.BluetoothUUID"
        
        /// Device Identifier
        case peripheral = "org.pureswift.GATT.CentralError.Peripheral"
    }
    
    public static var errorDomain: String {
        return "org.pureswift.GATT.CentralError"
    }
    
    /// The user-info dictionary.
    public var errorUserInfo: [String : Any] {
        
        var userInfo = [String : Any]()
        userInfo.reserveCapacity(1)
        
        switch self {
            
        case .timeout:
            
            let description = String(format: NSLocalizedString("The operation timed out.", comment: "org.pureswift.GATT.CentralError.timeout"))
            
            userInfo[NSLocalizedDescriptionKey] = description
            
        case let .disconnected(peripheral):
            
            let description = String(format: NSLocalizedString("The operation cannot be completed becuase the peripheral is disconnected.", comment: "org.pureswift.GATT.CentralError.disconnected"))
            
            userInfo[NSLocalizedDescriptionKey] = description
            userInfo[UserInfoKey.peripheral.rawValue] = peripheral
            
        case let .unknownPeripheral(peripheral):
            
            let description = String(format: NSLocalizedString("Unknown peripheral %@.", comment: "org.pureswift.GATT.CentralError.unknownPeripheral"), peripheral.identifier.uuidString)
            
            userInfo[NSLocalizedDescriptionKey] = description
            userInfo[UserInfoKey.peripheral.rawValue] = peripheral
            
        case let .invalidAttribute(uuid):
            
            let description = String(format: NSLocalizedString("Invalid attribute %@.", comment: "org.pureswift.GATT.CentralError.invalidAttribute"), uuid.description)
            
            userInfo[NSLocalizedDescriptionKey] = description
            userInfo[UserInfoKey.uuid.rawValue] = uuid
        }
        
        return userInfo
    }
}

#endif

#endif
