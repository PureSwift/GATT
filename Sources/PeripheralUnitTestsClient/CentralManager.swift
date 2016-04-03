//
//  CentralManager.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/3/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import Foundation
import CoreBluetooth

final class CentralManager: NSObject, CBCentralManagerDelegate {
    
    static let manager = CentralManager()
    
    lazy var internalManager: CBCentralManager = CBCentralManager(delegate: self, queue: nil)
    
    // MARK: - CBCentralManagerDelegate
    
    @objc func centralManagerDidUpdateState(central: CBCentralManager) {
        
        print("\(central) did update state")
    }
}