//
//  DarwinPeripheralError.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 7/20/26.
//

import Foundation

#if canImport(CoreBluetooth)

/// Errors for GATT Peripheral Manager
public enum DarwinPeripheralError: Error {

    /// The specified central is unknown or disconnected.
    case unknownCentral
}

// MARK: - CustomNSError

extension DarwinPeripheralError: CustomNSError {

    public static var errorDomain: String {
        return "org.pureswift.DarwinGATT.PeripheralError"
    }

    /// The user-info dictionary.
    public var errorUserInfo: [String : Any] {

        var userInfo = [String: Any](minimumCapacity: 1)

        switch self {

        case .unknownCentral:

            let description = String(format: NSLocalizedString("Unknown or disconnected central.", comment: "org.pureswift.GATT.PeripheralError.unknownCentral"))

            userInfo[NSLocalizedDescriptionKey] = description
        }

        return userInfo
    }
}

#endif
