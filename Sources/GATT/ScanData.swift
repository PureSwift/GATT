//
//  ScanResult.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 1/6/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

#if canImport(Foundation)
import Foundation
#endif
import Bluetooth

/// The data for a scan result.
public struct ScanData <Peripheral: Peer, Advertisement: AdvertisementData>: Equatable, Hashable, Sendable {
    
    #if hasFeature(Embedded)
    public typealias Timestamp = UInt64
    #else
    public typealias Timestamp = Foundation.Date
    #endif
    
    /// The discovered peripheral.
    public let peripheral: Peripheral
    
    /// Timestamp for when device was scanned.
    public let date: Timestamp
    
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

// MARK: - Codable

#if !hasFeature(Embedded)
extension ScanData: Encodable where Peripheral: Encodable, Advertisement: Encodable { }

extension ScanData: Decodable where Peripheral: Decodable, Advertisement: Decodable { }
#endif

// MARK: - Identifiable

extension ScanData: Identifiable {
    
    public var id: Peripheral.ID {
        return peripheral.id
    }
}
