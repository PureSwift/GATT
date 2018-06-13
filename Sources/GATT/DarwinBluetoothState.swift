//
//  DarwinBluetoothState.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 6/13/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation

#if os(macOS) || os(iOS) || os(tvOS) || (os(watchOS) && swift(>=3.2))

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

#endif
