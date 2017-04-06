//
//  Beacon.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/29/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import Foundation

/// Describes an iBeacon to be advertised.
public struct Beacon {
    
    /// The unique ID of the beacons being targeted.
    public var UUID: Foundation.UUID
    
    /// The value identifying a group of beacons.
    public var major: UInt16
    
    /// The value identifying a specific beacon within a group.
    public var minor: UInt16
    
    /// The received signal strength indicator (RSSI) value (measured in decibels) for the device.
    public var RSSI: Int8
    
    #if os(Linux) || XcodeLinux
    /// The advertising interval.
    public var interval: UInt16 = 200
    #endif
    
    public init(UUID: Foundation.UUID, major: UInt16, minor: UInt16, RSSI: Int8) {
        
        self.UUID = UUID
        self.major = major
        self.minor = minor
        self.RSSI = RSSI
    }
}
