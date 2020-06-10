//
//  File.swift
//  
//
//  Created by Alsey Coleman Miller on 6/10/20.
//

import Foundation
import Bluetooth
import GATT

public extension SynchronousCentral where Central == DarwinCentral {
    
    var state: DarwinBluetoothState {
        return central.state
    }
    
    func scan(filterDuplicates: Bool = true,
              with services: Set<BluetoothUUID>,
              _ foundDevice: @escaping (Result<ScanData<Peripheral, DarwinAdvertisementData>, Error>) -> ()) {
        
        
    }
}
