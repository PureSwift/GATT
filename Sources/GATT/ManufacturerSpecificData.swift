//
//  ManufacturerSpecificData.swift
//  
//
//  Created by Alsey Coleman Miller on 10/23/20.
//

import Foundation

#if canImport(BluetoothGAP)
import BluetoothGAP
public typealias ManufacturerSpecificData = GAPManufacturerSpecificData
#else
/// GATT Manufacturer Specific Data
public struct ManufacturerSpecificData: Equatable, Hashable {
    
    /// Company Identifier
    public var companyIdentifier: CompanyIdentifier
    
    public var additionalData: Data
    
    public init(companyIdentifier: CompanyIdentifier,
                additionalData: Data = Data()) {
        
        self.companyIdentifier = companyIdentifier
        self.additionalData = additionalData
    }
}

internal extension ManufacturerSpecificData {
    
    init?(data: Data) {
        
        guard data.count >= 2
            else { return nil }
        
        let companyIdentifier = CompanyIdentifier(rawValue: UInt16(littleEndian: unsafeBitCast((data[0], data[1]), to: UInt16.self)))
        let additionalData: Data
        if data.count > 2 {
            additionalData =  Data(data.suffix(from: 2))
        } else {
            additionalData = Data()
        }
        self.init(companyIdentifier: companyIdentifier, additionalData: additionalData)
    }
}
#endif
