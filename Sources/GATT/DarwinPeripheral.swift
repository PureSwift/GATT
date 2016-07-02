//
//  DarwinPeripheral.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/1/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import SwiftFoundation
import Bluetooth

#if os(OSX) || os(iOS) || os(watchOS) || os(tvOS)
    
    import Foundation
    import CoreBluetooth
    import CoreLocation
    
    /// The platform specific peripheral. 
    public typealias PeripheralManager = DarwinPeripheral
    
    public final class DarwinPeripheral: NSObject, NativePeripheral, CBPeripheralManagerDelegate {
        
        // MARK: - Properties
        
        public var log: ((String) -> ())?
        
        #if os(OSX)
        
        public var stateChanged: (CBPeripheralManagerState) -> () = { _ in }
        
        public var state: CBPeripheralManagerState {
            
            return internalManager.state
        }
        
        #else
        
        public var stateChanged: (CBPeripheralManagerState) -> () = { _ in }
        
        public var state: CBPeripheralManagerState {
            
            return unsafeBitCast(internalManager.state, to: CBPeripheralManagerState.self)
        }
        
        #endif
        
        public let localName: String
        
        public var willRead: ((central: Central, UUID: BluetoothUUID, value: Data, offset: Int) -> ATT.Error?)?
        
        public var willWrite: ((central: Central, UUID: BluetoothUUID, value: Data, newValue: Data) -> ATT.Error?)?
        
        public var didWrite: ((central: Central, UUID: BluetoothUUID, value: Data, newValue: Data) -> ())?
        
        // MARK: - Private Properties
        
        private lazy var internalManager: CBPeripheralManager = CBPeripheralManager(delegate: self, queue: self.queue)
        
        private lazy var queue: DispatchQueue = DispatchQueue(label: "\(self.dynamicType) Internal Queue", attributes: DispatchQueueAttributes.serial)
        
        private var poweredOnSemaphore: DispatchSemaphore!
        
        private var addServiceState: (semaphore: DispatchSemaphore, error: NSError?)?
        
        private var startAdvertisingState: (semaphore: DispatchSemaphore, error: NSError?)?
        
        private var services = [CBMutableService]()
        
        private var characteristicValues = [[(characteristic: CBMutableCharacteristic, value: Data)]]()
        
        // MARK: - Initialization
        
        public init(localName: String = "GATT Server") {
            
            self.localName = localName
        }
        
        // MARK: - Methods
        
        public func waitForPoweredOn() {
            
            // already on
            guard internalManager.state != .poweredOn else { return }
            
            // already waiting
            guard poweredOnSemaphore == nil else { let _ = poweredOnSemaphore.wait(timeout: .distantFuture); return }
            
            log?("Not powered on (State \(internalManager.state.rawValue))")
            
            poweredOnSemaphore = DispatchSemaphore(value: 0)
            
            let _ = poweredOnSemaphore.wait(timeout: .distantFuture)
            
            poweredOnSemaphore = nil
            
            assert(internalManager.state == .poweredOn)
            
            log?("Now powered on")
        }
        
        #if os(OSX)
        
        public func start() throws {
            
            let advertisementData = [CBAdvertisementDataLocalNameKey: localName]
            
            try start(advertisementData)
        }
        
        #endif

        #if XcodeLinux
        
        public func start(beacon: Beacon? = nil) throws {
            
            fatalError("Not supported on OS X")
        }
        
        #endif
        
        #if os(iOS)
        
        public func start(beacon: Beacon? = nil) throws {
        
            var advertisementData = [String: AnyObject]()
            
            if let beacon = beacon {
                
                let beaconRegion = CLBeaconRegion(proximityUUID: beacon.UUID, major: beacon.major, minor: beacon.minor, identifier: beacon.UUID.rawValue)
                
                let mutableDictionary = beaconRegion.peripheralData(withMeasuredPower: NSNumber(value: beacon.RSSI))
                
                advertisementData = NSDictionary.init(dictionary: mutableDictionary) as! [String: AnyObject]
            }
            
            advertisementData[CBAdvertisementDataLocalNameKey] = localName
            
            try start(advertisementData)
        }

        #endif
        
        @inline(__always)
        private func start(_ advertisementData: [String: AnyObject]) throws {
            
            assert(startAdvertisingState == nil, "Already started advertising")
            
            let semaphore = DispatchSemaphore(value: 0)
            
            startAdvertisingState = (semaphore, nil) // set semaphore
            
            internalManager.startAdvertising(advertisementData)
            
            let _ = semaphore.wait(timeout: .distantFuture)
            
            let error = startAdvertisingState?.error
            
            // clear
            startAdvertisingState = nil
            
            if let error = error {
                
                throw error
            }
        }
        
        public func stop() {
            
            internalManager.stopAdvertising()
        }
        
        public func add(service: Service) throws -> Int {
            
            assert(addServiceState == nil, "Already adding another Service")
            
            /// wait
            
            let semaphore = DispatchSemaphore(value: 0)
            
            addServiceState = (semaphore, nil) // set semaphore
            
            // add service
            let coreService = service.toCoreBluetooth()
            
            internalManager.add(coreService)
            
            let _ = semaphore.wait(timeout: .distantFuture)
            
            let error = addServiceState?.error
            
            // clear
            addServiceState = nil
            
            if let error = error {
                
                throw error
            }
            
            services.append(coreService)
            
            var characteristics = [(characteristic: CBMutableCharacteristic, value: Data)]()
            
            for (index, characteristic) in ((coreService.characteristics ?? []) as! [CBMutableCharacteristic]).enumerated()  {
                
                let data = service.characteristics[index].value
                
                characteristics.append((characteristic, data))
            }
            
            characteristicValues.append(characteristics)
            
            return services.endIndex
        }
        
        public func remove(service index: Int) {
            
            internalManager.remove(services[index])
            
            services.remove(at: index)
            characteristicValues.remove(at: index)
        }
        
        public func clear() {
            
            internalManager.removeAllServices()
            
            services = []
            characteristicValues = []
        }
        
        // MARK: Subscript
        
        public subscript(characteristic UUID: BluetoothUUID) -> Data {
            
            get { return self[characteristic(UUID)] }
            
            set { internalManager.updateValue(newValue, for: characteristic(UUID), onSubscribedCentrals: nil) }
        }
        
        // MARK: - CBPeripheralManagerDelegate
        
        public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
            
            log?("Did update state (\(peripheral.state == .poweredOn ? "Powered On" : "\(peripheral.state.rawValue)"))")
            
            stateChanged(unsafeBitCast(peripheral.state, to: CBPeripheralManagerState.self))
            
            if peripheral.state == .poweredOn && poweredOnSemaphore != nil {
                
                poweredOnSemaphore.signal()
            }
        }
        
        public func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: NSError?) {
            
            guard let semaphore = startAdvertisingState?.semaphore else { fatalError("Did not expect \(#function)") }
            
            startAdvertisingState?.error = error
            
            semaphore.signal()
        }
        
        @objc(peripheralManager:didAddService:error:) public func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: NSError?) {
            
            if let error = error {
                
                log?("Could not add service \(service.uuid) (\(error))")
                
            } else {
                
                log?("Added service \(service.uuid)")
            }
            
            guard let semaphore = addServiceState?.semaphore else { fatalError("Did not expect \(#function)") }
            
            addServiceState?.error = error
            
            semaphore.signal()
        }
        
        @objc(peripheralManager:didReceiveReadRequest:) public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
            
            let peer = Central(request.central)
            
            let value = self[request.characteristic].bytes
            
            let UUID = BluetoothUUID(coreBluetooth: request.characteristic.uuid)
            
            guard request.offset <= value.count
                else { internalManager.respond(to: request, withResult: .invalidOffset); return }
            
            if let error = willRead?(central: peer, UUID: UUID, value: Data(bytes: value), offset: request.offset) {
                
                internalManager.respond(to: request, withResult: CBATTError(rawValue: Int(error.rawValue))!)
                return
            }
            
            let requestedValue = request.offset == 0 ? value : Array(value.suffix(request.offset))
            
            request.value = Data(bytes: requestedValue)
            
            internalManager.respond(to: request, withResult: .success)
        }
        
        @objc(peripheralManager:didReceiveWriteRequests:) public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
            
            assert(requests.isEmpty == false)
            
            var newValues = [Data](repeating: Data(), count: requests.count)
            
            // validate write requests
            for (index, request) in requests.enumerated() {
                
                let peer = Central(request.central)
                
                let value = self[request.characteristic]
                
                let UUID = BluetoothUUID(coreBluetooth: request.characteristic.uuid)
                
                let newBytes = request.value ?? Data()
                
                var newValue = value
                
                newValue.bytes.replaceSubrange(request.offset ..< request.offset + newBytes.count, with: newBytes.bytes)
                
                if let error = willWrite?(central: peer, UUID: UUID, value: value, newValue: newValue) {
                    
                    internalManager.respond(to: requests[0], withResult: CBATTError(rawValue: Int(error.rawValue))!)
                    
                    return
                }
                
                // compute new data
                
                newValues[index] = newValue
            }
            
            // write new values
            for (index, request) in requests.enumerated() {
                
                let newValue = newValues[index]
                
                self[request.characteristic] = newValue
            }
            
            internalManager.respond(to: requests[0], withResult: .success)
        }
        
        // MARK: - Private Methods
        
        /// Find the characteristic with the specified UUID.
        private func characteristic(_ UUID: BluetoothUUID) -> CBMutableCharacteristic {
            
            var foundCharacteristic: CBMutableCharacteristic!
            
            for service in services {
                
                for characteristic in (service.characteristics ?? []) as! [CBMutableCharacteristic] {
                    
                    #if os(OSX)
                        let foundation = characteristic.uuid!
                    #elseif os(iOS)
                        let foundation = characteristic.uuid
                    #endif
                    
                    guard UUID != BluetoothUUID(coreBluetooth: foundation)
                        else { foundCharacteristic = characteristic; break }
                }
            }
            
            guard foundCharacteristic != nil
                else { fatalError("No Characterstic with UUID \(UUID)") }
            
            return foundCharacteristic
        }
        
        // MARK: Subscript
        
        private subscript(characteristic: CBCharacteristic) -> Data {
            
            get {
                
                for service in characteristicValues {
                    
                    for characteristicValue in service {
                        
                        if characteristicValue.characteristic === characteristic {
                            
                            return characteristicValue.value
                        }
                    }
                }
                
                fatalError("No stored characteristic matches \(characteristic)")
            }
            
            set {
                
                for (serviceIndex, service) in characteristicValues.enumerated() {
                    
                    for (characteristicIndex, characteristicValue) in service.enumerated() {
                        
                        if characteristicValue.characteristic === characteristic {
                            
                            characteristicValues[serviceIndex][characteristicIndex].value = newValue
                            return
                        }
                    }
                }
                
                fatalError("No stored characteristic matches \(characteristic)")
            }
        }
    }

#endif
