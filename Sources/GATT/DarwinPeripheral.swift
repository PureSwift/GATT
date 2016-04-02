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
    import Bluetooth
    
    /// The platform specific peripheral. 
    public typealias Server = DarwinPeripheral
    
    public final class DarwinPeripheral: NSObject, CBPeripheralManagerDelegate, PeripheralManager {
        
        // MARK: - Properties
        
        public var stateChanged: (CBPeripheralManagerState) -> () = { _ in }
        
        public var state: CBPeripheralManagerState {
            
            return internalManager.state
        }
        
        public var read: ()
        
        // MARK: - Private Properties
        
        private var internalManager: CBPeripheralManager!
        
        private let queue: dispatch_queue_t = dispatch_queue_create("\(self.dynamicType) Internal Queue", nil)
        
        private var addServiceState: (semaphore: dispatch_semaphore_t, error: NSError?)?
        
        private var services: [Bluetooth.UUID: CBMutableService] = [:]
        
        // MARK: - Initialization
        
        public override init() {
            
            super.init()
            
            self.internalManager = CBPeripheralManager(delegate: self, queue: queue)
        }
        
        // MARK: - Methods
        
        public func add(service: Service) throws {
            
            assert(addServiceState == nil, "Already adding another Service")
            
            /// wait
            
            let semaphore = dispatch_semaphore_create(0)
            
            addServiceState = (semaphore, nil) // set semaphore
            
            // add service
            let coreService = service.toCoreBluetooth()
            internalManager.addService(coreService)
            
            dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)
            
            let error = addServiceState?.error
            
            // clear
            addServiceState = nil
            
            if let error = error {
                
                throw error
            }
            
            services[service.UUID] = coreService
        }
        
        public func remove(service: Bluetooth.UUID) {
            
            guard let coreService = services[service]
                else { fatalError("No Service with UUID \(service) exists") }
            
            internalManager.removeService(coreService)
        }
        
        public func clear() {
            
            internalManager.removeAllServices()
            
            services = [:]
        }
        
        // MARK: - CBPeripheralManagerDelegate
        
        public func peripheralManagerDidUpdateState(peripheral: CBPeripheralManager) {
            
            stateChanged(peripheral.state)
        }
        
        public func peripheralManager(peripheral: CBPeripheralManager, didAddService service: CBService, error: NSError?) {
            
            guard let semaphore = addServiceState?.semaphore else { fatalError("Did not expect \(#function)") }
            
            addServiceState?.error = error
            
            dispatch_semaphore_signal(semaphore)
        }
        
        public func peripheralManager(peripheral: CBPeripheralManager, didReceiveReadRequest request: CBATTRequest) {
            
            
        }
        
        public func peripheralManager(peripheral: CBPeripheralManager, didReceiveWriteRequests requests: [CBATTRequest]) {
            
            
        }
    }

#endif
