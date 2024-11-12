//
//  CharacteristicProperty.swift
//  
//
//  Created by Alsey Coleman Miller on 10/23/20.
//

@_exported import Bluetooth
#if canImport(BluetoothGATT)
@_exported import BluetoothGATT
public typealias CharacteristicProperties = BluetoothGATT.GATTCharacteristicProperties
#else
/// GATT Characteristic Properties Bitfield valuess
public struct CharacteristicProperties: OptionSet, Hashable, Sendable {
    
    public var rawValue: UInt8
    
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }
}

// MARK: - ExpressibleByIntegerLiteral

extension CharacteristicProperties: ExpressibleByIntegerLiteral {
    
    public init(integerLiteral value: UInt8) {
        self.rawValue = value
    }
}

// MARK: CustomStringConvertible

extension CharacteristicProperties: CustomStringConvertible, CustomDebugStringConvertible {
    
    #if hasFeature(Embedded)
    public var description: String {
        "0x" + rawValue.toHexadecimal()
    }
    #else
    @inline(never)
    public var description: String {
        let descriptions: [(CharacteristicProperties, StaticString)] = [
            (.broadcast,            ".broadcast"),
            (.read,                 ".read"),
            (.write,                ".write"),
            (.notify,               ".notify"),
            (.indicate,             ".indicate"),
            (.signedWrite,          ".signedWrite"),
            (.extendedProperties,   ".extendedProperties")
        ]
        return buildDescription(descriptions)
    }
    #endif

    /// A textual representation of the file permissions, suitable for debugging.
    public var debugDescription: String { self.description }
}

// MARK: - Options

public extension CharacteristicProperties {
    
    static var broadcast: CharacteristicProperties            { 0x01 }
    static var read: CharacteristicProperties                 { 0x02 }
    static var writeWithoutResponse: CharacteristicProperties { 0x04 }
    static var write: CharacteristicProperties                { 0x08 }
    static var notify: CharacteristicProperties               { 0x10 }
    static var indicate: CharacteristicProperties             { 0x20 }
    
    /// Characteristic supports write with signature
    static var signedWrite: CharacteristicProperties          { 0x40 } // BT_GATT_CHRC_PROP_AUTH
    
    static var extendedProperties: CharacteristicProperties   { 0x80 }
}
#endif
