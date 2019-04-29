//
//  DarwinCentralError.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 7/14/18.
//

import Foundation
import Bluetooth

#if canImport(CoreBluetooth)

/// Errors for GATT Central Manager
public enum DarwinCentralError: Error {
    
    /// Bluetooth controller is not enabled.
    case invalidState(DarwinBluetoothState)
}

// MARK: - CustomNSError

extension DarwinCentralError: CustomNSError {
    
    public enum UserInfoKey: String {
        
        /// State
        case state = "org.pureswift.DarwinGATT.CentralError.BluetoothState"
    }
    
    public static var errorDomain: String {
        return "org.pureswift.DarwinGATT.CentralError"
    }
    
    /// The user-info dictionary.
    public var errorUserInfo: [String : Any] {
        
        var userInfo = [String: Any](minimumCapacity: 2)
        
        switch self {
            
        case let .invalidState(state):
            
            let description = String(format: NSLocalizedString("Invalid state %@.", comment: "org.pureswift.GATT.CentralError.invalidState"), "\(state)")
            
            userInfo[NSLocalizedDescriptionKey] = description
            userInfo[UserInfoKey.state.rawValue] = state
        }
        
        return userInfo
    }
}

#endif
