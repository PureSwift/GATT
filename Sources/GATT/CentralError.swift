//
//  CentralError.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 7/14/18.
//

import Foundation
import Bluetooth

/// Errors for GATT Central Manager
public enum CentralError: Error {
    
    /// Operation timeout.
    case timeout
    
    /// Peripheral is disconnected.
    case disconnected
    
    /// Peripheral from previous scan / unknown.
    case unknownPeripheral
    
    /// The specified attribute was not found.
    case invalidAttribute(BluetoothUUID)
}

// MARK: - CustomNSError

extension CentralError: CustomNSError {
    
    public enum UserInfoKey: String {
        
        /// Bluetooth UUID value (for characteristic or service).
        case uuid = "org.pureswift.GATT.CentralError.BluetoothUUID"
    }
    
    public static var errorDomain: String {
        return "org.pureswift.GATT.CentralError"
    }
    
    /// The user-info dictionary.
    public var errorUserInfo: [String : Any] {
        
        var userInfo = [String: Any](minimumCapacity: 2)
        
        switch self {
            
        case .timeout:
            
            let description = String(format: NSLocalizedString("The operation timed out.", comment: "org.pureswift.GATT.CentralError.timeout"))
            
            userInfo[NSLocalizedDescriptionKey] = description
            
        case .disconnected:
            
            let description = String(format: NSLocalizedString("The operation cannot be completed becuase the peripheral is disconnected.", comment: "org.pureswift.GATT.CentralError.disconnected"))
            
            userInfo[NSLocalizedDescriptionKey] = description
            
        case .unknownPeripheral:
            
            let description = String(format: NSLocalizedString("Unknown peripheral.", comment: "org.pureswift.GATT.CentralError.unknownPeripheral"))
            
            userInfo[NSLocalizedDescriptionKey] = description
            
        case let .invalidAttribute(uuid):
            
            #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
            let description = String(format: NSLocalizedString("Invalid attribute %@.", comment: "org.pureswift.GATT.CentralError.invalidAttribute"), uuid.description)
            #else
            let description = "Invalid attribute \(uuid)"
            #endif
            
            userInfo[NSLocalizedDescriptionKey] = description
            userInfo[UserInfoKey.uuid.rawValue] = uuid
        }
        
        return userInfo
    }
}
