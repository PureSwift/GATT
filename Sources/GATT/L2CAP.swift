//
//  L2CAP.swift
//  
//
//  Created by Alsey Coleman Miller on 4/18/22.
//

#if canImport(BluetoothHCI)
import Bluetooth
import BluetoothHCI

internal extension L2CAPConnection {
    
    /// Creates a client socket for an L2CAP connection.
    static func lowEnergyClient(
        address localAddress: BluetoothAddress,
        destination: HCILEAdvertisingReport.Report
    ) throws -> Self {
        try lowEnergyClient(
            address: localAddress,
            destination: destination.address,
            isRandom: destination.addressType == .random
        )
    }
}

#endif
