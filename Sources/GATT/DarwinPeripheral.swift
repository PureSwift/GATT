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
    
    public typealias Peripheral = DarwinPeripheral
    
    public final class DarwinPeripheral: NSObject, CBPeripheralManagerDelegate, PeripheralManager {
        
        // MARK: - Properties
        
        public var stateChanged: (CBPeripheralManagerState) -> () = { _ in }
        
        public var state: CBPeripheralManagerState {
            
            return internalManager.state
        }
        
        // MARK: - Private Properties
        
        private let internalManager: CBPeripheralManager
        
        private let queue: dispatch_queue_t
        
        private var addServiceSemaphore: dispatch_semaphore_t?
        
        private var addServiceError: NSError?
        
        // MARK: - Initialization
        
        public override init() {
            
            super.init()
            
            queue = dispatch_queue_create("GATT.Peripheral Internal Queue", nil)
            
            internalManager = CBPeripheralManager(delegate: self, queue: queue)
        }
        
        // MARK: - Methods
        
        public func add(service: Service) throws {
            
            assert(addServiceSemaphore == nil, "Already adding another Service")
            
            /// wait
            
            let semaphore = dispatch_semaphore_create(0)
            
            addServiceSemaphore = semaphore // set semaphore
            
            // add service
            internalManager.addService(service.toCoreBluetooth())
            
            dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)
            
            let error = addServiceError
            
            // clear
            addServiceError = nil
            addServiceSemaphore = nil
            
            if let error = error {
                
                throw error
            }
        }
        
        // MARK: - CBPeripheralManagerDelegate
        
        public func peripheralManagerDidUpdateState(peripheral: CBPeripheralManager) {
            
            stateChanged(peripheral.state)
        }
        
        public func peripheralManager(peripheral: CBPeripheralManager, didAddService service: CBService, error: NSError?) {
            
            guard let semaphore = addServiceSemaphore else { fatalError("Did not expect \(#function)") }
            
            addServiceError = error
            
            dispatch_semaphore_signal(semaphore)
        }
    }

#endif
