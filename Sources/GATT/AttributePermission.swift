//
//  AttributePermission.swift
//  
//
//  Created by Alsey Coleman Miller on 10/23/20.
//

@_exported import Bluetooth
#if canImport(BluetoothGATT)
@_exported import BluetoothGATT
public typealias AttributePermissions = BluetoothGATT.ATTAttributePermissions
#else
/// ATT attribute permission bitfield values. Permissions are grouped as
/// "Access", "Encryption", "Authentication", and "Authorization". A bitmask of
/// permissions is a byte that encodes a combination of these.
@frozen
public struct AttributePermissions: OptionSet, Equatable, Hashable, Sendable {
    
    public var rawValue: UInt8
    
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }
}

// MARK: - ExpressibleByIntegerLiteral

extension AttributePermissions: ExpressibleByIntegerLiteral {
    
    public init(integerLiteral value: UInt8) {
        self.rawValue = value
    }
}

// MARK: - CustomStringConvertible

extension AttributePermissions: CustomStringConvertible, CustomDebugStringConvertible {
    
    #if hasFeature(Embedded)
    public var description: String {
        "0x" + rawValue.toHexadecimal()
    }
    #else
    @inline(never)
    public var description: String {
        let descriptions: [(AttributePermissions, StaticString)] = [
            (.read, ".read"),
            (.write, ".write"),
            (.readEncrypt, ".readEncrypt"),
            (.writeEncrypt, ".writeEncrypt"),
            (.readAuthentication, ".readAuthentication"),
            (.writeAuthentication, ".writeAuthentication"),
            (.authorized, ".authorized"),
            (.noAuthorization, ".noAuthorization"),
        ]
        return buildDescription(descriptions)
    }
    #endif

    /// A textual representation of the file permissions, suitable for debugging.
    public var debugDescription: String { self.description }
}

// MARK: - Options

public extension AttributePermissions {
    
    // Access
    static var read: AttributePermissions                     { 0x01 }
    static var write: AttributePermissions                    { 0x02 }
    
    // Encryption
    static var encrypt: AttributePermissions                  { [.readEncrypt, .writeEncrypt] }
    static var readEncrypt: AttributePermissions              { 0x04 }
    static var writeEncrypt: AttributePermissions             { 0x08 }
    
    // The following have no effect on Darwin
    
    // Authentication
    static var authentication: AttributePermissions           { [.readAuthentication, .writeAuthentication] }
    static var readAuthentication: AttributePermissions       { 0x10 }
    static var writeAuthentication: AttributePermissions      { 0x20 }
    
    // Authorization
    static var authorized: AttributePermissions               { 0x40 }
    static var noAuthorization: AttributePermissions          { 0x80 }
}

#endif
