//
//  DarwinBluetoothState.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 6/13/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

#if canImport(CoreBluetooth)

import Foundation

/// Darwin Bluetooth State
///
/// - SeeAlso: [CBManagerState](https://developer.apple.com/documentation/corebluetooth/cbmanagerstate).
@objc public enum DarwinBluetoothState: Int {
    
    case unknown
    case resetting
    case unsupported
    case unauthorized
    case poweredOff
    case poweredOn
}

// MARK: - CustomStringConvertible

extension DarwinBluetoothState: CustomStringConvertible {
    
    public var description: String {
        
        switch self {
        case .unknown:
            return "Unknown"
        case .resetting:
            return "Resetting"
        case .unsupported:
            return "Unsupported"
        case .unauthorized:
            return "Unauthorized"
        case .poweredOff:
            return "Powered Off"
        case .poweredOn:
            return "Powered On"
        }
    }
}

#endif
