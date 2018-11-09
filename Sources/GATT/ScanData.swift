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
public struct ScanData <Peripheral: Peer, Advertisement: AdvertisementDataProtocol>: Equatable {
    
    /// The discovered peripheral.
    public let peripheral: Peripheral
    
    /// Timestamp for when device was scanned.
    public let date: Date
    
    /// The current received signal strength indicator (RSSI) of the peripheral, in decibels.
    public let rssi: Double
    
    /// Advertisement data.
    public let advertisementData: Advertisement
    
    /// A Boolean value that indicates whether the advertising event type is connectable.
    public let isConnectable: Bool
    
    public init(peripheral: Peripheral,
                date: Date = Date(),
                rssi: Double,
                advertisementData: Advertisement,
                isConnectable: Bool) {
        
        self.peripheral = peripheral
        self.date = date
        self.rssi = rssi
        self.advertisementData = advertisementData
        self.isConnectable = isConnectable
    }
}
