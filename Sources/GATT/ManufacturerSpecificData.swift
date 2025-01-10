//
//  ManufacturerSpecificData.swift
//  
//
//  Created by Alsey Coleman Miller on 10/23/20.
//

@_exported import Bluetooth
#if canImport(BluetoothGAP)
@_exported import BluetoothGAP
public typealias ManufacturerSpecificData = GAPManufacturerSpecificData
#else
/// GATT Manufacturer Specific Data
public struct ManufacturerSpecificData <Data: DataContainer> : Equatable, Hashable, Sendable {
    
    internal let data: Data // Optimize for CoreBluetooth / iOS
    
    public init?(data: Data) {
        guard data.count >= 2
            else { return nil }
        self.data = data
    }
}

public extension ManufacturerSpecificData {
        
    /// Company Identifier
    var companyIdentifier: CompanyIdentifier {
        
        get {
            assert(data.count >= 2, "Invalid manufacturer data")
            return CompanyIdentifier(rawValue: UInt16(littleEndian: unsafeBitCast((data[0], data[1]), to: UInt16.self)))
        }
        
        set { self = ManufacturerSpecificData(companyIdentifier: newValue, additionalData: additionalData) }
    }
    
    var additionalData: Data {
        
        get {
            if data.count > 2 {
                return Data(data.suffix(from: 2))
            } else {
                return Data()
            }
        }
        
        set { self = ManufacturerSpecificData(companyIdentifier: companyIdentifier, additionalData: newValue) }
    }
    
    init(companyIdentifier: CompanyIdentifier,
         additionalData: Data = Data()) {
        
        var data = Data()
        data.reserveCapacity(2 + additionalData.count)
        data += companyIdentifier.rawValue.littleEndian
        data += additionalData
        self.data = data
    }
}

#endif
