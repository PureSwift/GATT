//
//  Hexadecimal.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 7/18/26.
//  Copyright © 2026 PureSwift. All rights reserved.
//

#if hasFeature(Embedded)

internal extension FixedWidthInteger {

    /// Uppercase, zero-padded, big-endian hexadecimal representation.
    ///
    /// GATT keeps its own copy because `Bluetooth`'s equivalent helper is
    /// `internal`. It exists only for the Embedded Swift `description`
    /// implementations, which can't rely on Foundation or `String(radix:)`.
    func toHexadecimal() -> String {
        func hexDigit(_ value: UInt8) -> Unicode.Scalar {
            Unicode.Scalar(value < 10 ? 0x30 + value : 0x41 + (value - 10))
        }
        var string = ""
        var index = MemoryLayout<Self>.size
        while index > 0 {
            index -= 1
            let byte = UInt8(truncatingIfNeeded: self >> (index * 8))
            string.unicodeScalars.append(hexDigit(byte >> 4))
            string.unicodeScalars.append(hexDigit(byte & 0x0F))
        }
        return string
    }
}

#endif
