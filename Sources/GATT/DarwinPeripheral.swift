//
//  DarwinPeripheral.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/1/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

#if os(OSX) || os(iOS) || os(tvOS)
    
    import Foundation
    import CoreBluetooth
    
    public final class Peripheral: NSObject, CBPeripheralManagerDelegate, PeripheralManager {
        
        // MARK: - Properties
        
        private let internalManager: CBPeripheralManager
        
        private let queue: dispatch_queue_t
        
        // MARK: - Initialization
        
        public override init() {
            
            super.init()
            
            queue = dispatch_queue_create("GATT.Peripheral Internal Queue", nil)
            
            internalManager = CBPeripheralManager(delegate: self, queue: queue)
        }
        
        // MARK: - Methods
        
        
        
        // MARK: - CBPeripheralManagerDelegate
        
        
    }

#endif
