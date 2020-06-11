//
//  File.swift
//  
//
//  Created by Alsey Coleman Miller on 6/10/20.
//

import Foundation
import Dispatch
import Bluetooth
import GATT

public extension SynchronousCentral where Central == DarwinCentral {
    
    /// The current state of the manager.
    var state: DarwinBluetoothState {
        return central.state
    }
    
    /// Scans for peripherals that are advertising services.
    func scan(filterDuplicates: Bool = true,
              with services: Set<BluetoothUUID>,
              foundDevice: @escaping (Result<ScanData<Peripheral, DarwinAdvertisementData>, Error>) -> ()) {
        
        fatalError("Segmentation fault, can't compile")
        /*
        // block while scanning
        let semaphore = DispatchSemaphore(value: 0)
        let oldScanningChanged = central.scanningChanged
        central.scanningChanged = { if $0 == false { semaphore.signal() } }
        central.scan(filterDuplicates: filterDuplicates, with: services) { (result) in
            switch result {
            case let .failure(error):
                foundDevice(.failure(error))
                semaphore.signal()
            case let .success(scanData):
                foundDevice(.success(scanData))
            }
        }
        try semaphore.wait()
        central.scanningChanged = oldScanningChanged*/
    }
}
