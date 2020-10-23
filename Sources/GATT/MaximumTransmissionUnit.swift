//
//  MaximumTransmissionUnit.swift
//  
//
//  Created by Alsey Coleman Miller on 10/23/20.
//

import Foundation
@_exported import Bluetooth
#if canImport(BluetoothGATT)
@_exported import BluetoothGATT
public typealias MaximumTransmissionUnit = ATTMaximumTransmissionUnit
#else
/// GATT Maximum Transmission Unit
public struct MaximumTransmissionUnit: RawRepresentable, Equatable, Hashable {
    
    public let rawValue: UInt16
    
    public init?(rawValue: UInt16) {
        
        guard rawValue <= MaximumTransmissionUnit.max.rawValue,
            rawValue >= MaximumTransmissionUnit.min.rawValue
            else { return nil }
        
        self.rawValue = rawValue
    }
    
    fileprivate init(_ unsafe: UInt16) {
        self.rawValue = unsafe
    }
}

private extension MaximumTransmissionUnit {
    
    var isValid: Bool {
        
        return (MaximumTransmissionUnit.min.rawValue ... MaximumTransmissionUnit.max.rawValue).contains(rawValue)
    }
}

public extension MaximumTransmissionUnit {
    
    static var `default`: MaximumTransmissionUnit { return MaximumTransmissionUnit(23) }
    
    static var min: MaximumTransmissionUnit { return .default }
    
    static var max: MaximumTransmissionUnit { return MaximumTransmissionUnit(517) }
    
    init(server: UInt16,
         client: UInt16) {
        
        let mtu = Swift.min(Swift.max(Swift.min(client, server), MaximumTransmissionUnit.default.rawValue), MaximumTransmissionUnit.max.rawValue)
        
        self.init(mtu)
        
        assert(isValid)
    }
}

// MARK: - CustomStringConvertible

extension MaximumTransmissionUnit: CustomStringConvertible {
    
    public var description: String {
        
        return rawValue.description
    }
}

// MARK: - Comparable

extension MaximumTransmissionUnit: Comparable {
    
    public static func < (lhs: MaximumTransmissionUnit, rhs: MaximumTransmissionUnit) -> Bool {
        
        return lhs.rawValue < rhs.rawValue
    }
}
#endif
