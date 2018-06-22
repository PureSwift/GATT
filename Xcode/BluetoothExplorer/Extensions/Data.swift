//
//  Data.swift
//  BluetoothExplorer
//
//  Created by Alsey Coleman Miller on 6/20/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import Bluetooth

internal extension Data {
    
    enum HexEncodingOption: Int, BitMaskOption {
        
        case upperCase = 0b01
        
        static let all: Set<HexEncodingOption> = [.upperCase]
    }
    
    func toHexadecimal(options: BitMaskOptionSet<HexEncodingOption> = []) -> String {
        let format = options.contains(.upperCase) ? "%02hhX" : "%02hhx"
        return map { String(format: format, $0) }.joined()
    }
    
    init?(hexadecimal string: String) {
        
        /*
        let elements = Array(string.utf8)
        
        for index in stride(from: 0, to: string.count, by: 2) {
            
            guard let byte = UInt8(String(elements[index ..< index.advanced(by: 2)]), radix: 16)
                else { return nil }
            
            
        }*/
        
        return nil
    }
}
