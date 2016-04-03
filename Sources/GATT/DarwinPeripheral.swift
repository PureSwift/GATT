//
//  DarwinPeripheral.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/1/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import SwiftFoundation
import Bluetooth

#if os(OSX) || os(iOS) || os(tvOS)
    
    import Foundation
    import CoreBluetooth
    
    /// The platform specific peripheral. 
    public typealias Server = DarwinPeripheral
    
    public final class DarwinPeripheral: NSObject, CBPeripheralManagerDelegate, PeripheralManager {
        
        // MARK: - Properties
        
        public var stateChanged: (CBPeripheralManagerState) -> () = { _ in }
        
        public var state: CBPeripheralManagerState {
            
            return internalManager.state
        }
        
        public var willRead: ((UUID: Bluetooth.UUID, value: Data, offset: Int) -> ATT.Error?)?
        
        public var willWrite: ((UUID: Bluetooth.UUID, value: Data, newValue: (newValue: Data, newBytes: Data, offset: Int)) -> ATT.Error?)?
        
        // MARK: - Private Properties
        
        private var internalManager: CBPeripheralManager!
        
        private let queue: dispatch_queue_t = dispatch_queue_create("\(self.dynamicType) Internal Queue", nil)
        
        private var addServiceState: (semaphore: dispatch_semaphore_t, error: NSError?)?
        
        private var services = [CBMutableService]()
        
        // MARK: - Initialization
        
        public override init() {
            
            super.init()
            
            self.internalManager = CBPeripheralManager(delegate: self, queue: queue)
        }
        
        // MARK: - Methods
        
        public func add(service: Service) throws -> Int {
            
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
            
            services.append(coreService)
            
            return services.endIndex
        }
        
        public func remove(service index: Int) {
            
            internalManager.removeService(services[index])
            
            services.removeAtIndex(index)
        }
        
        public func clear() {
            
            internalManager.removeAllServices()
            
            services = []
        }
        
        public func update(value: Data, forCharacteristic UUID: Bluetooth.UUID) {
            
            internalManager.updateValue(value.toFoundation(), forCharacteristic: characteristic(UUID), onSubscribedCentrals: nil)
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
            
            let value = Data(foundation: request.characteristic.value ?? NSData()).byteValue
            
            let UUID = Bluetooth.UUID(foundation: request.characteristic.UUID)
            
            guard request.offset <= value.count
                else { internalManager.respondToRequest(request, withResult: .InvalidOffset); return }
            
            if let error = willRead?(UUID: UUID, value: Data(byteValue: value), offset: request.offset) {
                
                internalManager.respondToRequest(request, withResult: CBATTError(rawValue: Int(error.rawValue))!)
                return
            }
            
            let requestedValue = request.offset == 0 ? value : Array(value.suffixFrom(request.offset))
            
            request.value = Data(byteValue: requestedValue).toFoundation()
            
            internalManager.respondToRequest(request, withResult: .Success)
        }
        
        public func peripheralManager(peripheral: CBPeripheralManager, didReceiveWriteRequests requests: [CBATTRequest]) {
            
            assert(requests.isEmpty == false)
            
            var newValues = [Data](count: requests.count, repeatedValue: (Data()))
            
            // validate write requests
            for (index, request) in requests.enumerate() {
                
                let value = Data(foundation: request.characteristic.value ?? NSData())
                
                let UUID = Bluetooth.UUID(foundation: request.characteristic.UUID)
                
                let newBytes = Data(foundation: request.value ?? NSData())
                
                var newValue = value
                
                newValue.byteValue.replaceRange(request.offset ..< request.offset + newBytes.byteValue.count, with: newBytes.byteValue)
                
                if let error = willWrite?(UUID: UUID, value: value, newValue: (newValue, newBytes, request.offset)) {
                    
                    internalManager.respondToRequest(requests[0], withResult: CBATTError(rawValue: Int(error.rawValue))!)
                    
                    return
                }
                
                // compute new data
                
                newValues[index] = newValue
            }
            
            // write new values
            for (index, request) in requests.enumerate() {
                
                let newValue = newValues[index]
                
                (request.characteristic as! CBMutableCharacteristic).value = newValue.toFoundation()
            }
            
            internalManager.respondToRequest(requests[0], withResult: .Success)
        }
        
        // MARK: - Private Methods
        
        /// Find the characteristic with the specified UUID.
        private func characteristic(UUID: Bluetooth.UUID) -> CBMutableCharacteristic {
            
            var foundCharacteristic: CBMutableCharacteristic!
            
            for service in services {
                
                for characteristic in (service.characteristics ?? []) as! [CBMutableCharacteristic] {
                    
                    guard UUID != Bluetooth.UUID(foundation: characteristic.UUID!)
                        else { foundCharacteristic = characteristic; break }
                }
            }
            
            guard foundCharacteristic != nil
                else { fatalError("No Characterstic with UUID \(UUID)") }
            
            return foundCharacteristic
        }
    }

#endif
