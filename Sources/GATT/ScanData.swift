//
//  ScanResult.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 1/6/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import Bluetooth

/// The data for a scan result.
public struct ScanData {
    
    /// Timestamp for when device was scanned.
    public let date: Date
    
    /// The discovered peripheral.
    public let peripheral: Peripheral
    
    /// The current received signal strength indicator (RSSI) of the peripheral, in decibels.
    public let rssi: Double
    
    /// Advertisement data.
    public let advertisementData: AdvertisementData
}

// MARK: - Equatable

extension ScanData: Equatable {
    
    public static func == (lhs: ScanData, rhs: ScanData) -> Bool {
        
        return lhs.date == rhs.date
            && lhs.peripheral == rhs.peripheral
            && lhs.rssi == rhs.rssi
            && lhs.advertisementData == rhs.advertisementData
    }
}

