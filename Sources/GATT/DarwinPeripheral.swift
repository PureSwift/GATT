//
//  DarwinPeripheral.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/1/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import Foundation
import Bluetooth

#if os(macOS) || os(iOS)
    
    import CoreBluetooth
    import CoreLocation
    
    /// The platform specific peripheral.
    public typealias PeripheralManager = DarwinPeripheral

    public final class DarwinPeripheral: NSObject, NativePeripheral, CBPeripheralManagerDelegate {
        
        // MARK: - Properties
        
        public var log: ((String) -> ())?
        
        public var stateChanged: (DarwinBluetoothState) -> () = { _ in }
        
        public var state: DarwinBluetoothState {
            
            return unsafeBitCast(internalManager.state, to: DarwinBluetoothState.self)
        }
        
        public let localName: String?
        
        public var willRead: ((_ central: Central, _ uuid: BluetoothUUID, _ value: Data, _ offset: Int) -> ATT.Error?)?
        
        public var willWrite: ((_ central: Central, _ uuid: BluetoothUUID, _ value: Data, _ newValue: Data) -> ATT.Error?)?
        
        public var didWrite: ((_ central: Central, _ uuid: BluetoothUUID, _ value: Data, _ newValue: Data) -> ())?
        
        // MARK: - Private Properties
        
        private lazy var internalManager: CBPeripheralManager = CBPeripheralManager(delegate: self, queue: self.queue)
        
        private lazy var queue: DispatchQueue = DispatchQueue(label: "\(type(of: self)) Internal Queue", attributes: [])
        
        private var addServiceState: (semaphore: DispatchSemaphore, error: Error?)?
        
        private var startAdvertisingState: (semaphore: DispatchSemaphore, error: Error?)?
        
        private var services = [CBMutableService]()
        
        private var characteristicValues = [[(characteristic: CBMutableCharacteristic, value: Data)]]()
        
        // MARK: - Initialization
        
        public init(localName: String? = nil) {
            
            self.localName = localName
        }
        
        // MARK: - Methods
        
        #if os(iOS)
        
        public func start(beacon: AppleBeacon? = nil) throws {
        
            var advertisementData = [String: AnyObject]()
            
            if let beacon = beacon {
                
                let beaconRegion = CLBeaconRegion(proximityUUID: beacon.uuid,
                                                  major: beacon.major,
                                                  minor: beacon.minor,
                                                  identifier: beacon.uuid.rawValue)
                
                let mutableDictionary = beaconRegion.peripheralData(withMeasuredPower: NSNumber(value: beacon.rssi))
                
                advertisementData = NSDictionary.init(dictionary: mutableDictionary) as! [String: AnyObject]
            }
            
            if let name = localName {
                
                advertisementData[CBAdvertisementDataLocalNameKey] = name as NSString
            }
            
            try start(advertisementData)
        }

        #endif
        
        public func start() throws {
            
            var advertisementData = [String : AnyObject]()
            
            if let localName = self.localName {
                
                advertisementData[CBAdvertisementDataLocalNameKey] = localName as NSString
            }
            
            try start(advertisementData)
        }
        
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
        
        public func add(service: GATT.Service) throws -> Int {
            
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
        
        @objc(peripheralManagerDidUpdateState:)
        public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
            
            let state = unsafeBitCast(peripheral.state, to: DarwinBluetoothState.self)
            
            log?("Did update state \(state)")
            
            stateChanged(state)
        }
        
        @objc(peripheralManagerDidStartAdvertising:error:)
        public func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
            
            guard let semaphore = startAdvertisingState?.semaphore else { fatalError("Did not expect \(#function)") }
            
            startAdvertisingState?.error = error
            
            semaphore.signal()
        }
        
        @objc(peripheralManager:didAddService:error:)
        public func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
            
            if let error = error {
                
                log?("Could not add service \(service.uuid) (\(error))")
                
            } else {
                
                log?("Added service \(service.uuid)")
            }
            
            guard let semaphore = addServiceState?.semaphore else { fatalError("Did not expect \(#function)") }
            
            addServiceState?.error = error
            
            semaphore.signal()
        }
        
        @objc(peripheralManager:didReceiveReadRequest:)
        public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
            
            let peer = Central(request.central)
            
            let value = self[request.characteristic]
            
            let UUID = BluetoothUUID(coreBluetooth: request.characteristic.uuid)
            
            guard request.offset <= value.count
                else { internalManager.respond(to: request, withResult: .invalidOffset); return }
            
            if let error = willRead?(peer, UUID, value, request.offset) {
                
                internalManager.respond(to: request, withResult: CBATTError.Code(rawValue: Int(error.rawValue))!)
                return
            }
            
            let requestedValue = request.offset == 0 ? value : Data(value.suffix(request.offset))
            
            request.value = requestedValue
            
            internalManager.respond(to: request, withResult: .success)
        }
        
        @objc(peripheralManager:didReceiveWriteRequests:)
        public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
            
            assert(requests.isEmpty == false)
            
            var newValues = [Data](repeating: Data(), count: requests.count)
            
            // validate write requests
            for (index, request) in requests.enumerated() {
                
                let peer = Central(request.central)
                
                let value = self[request.characteristic]
                
                let UUID = BluetoothUUID(coreBluetooth: request.characteristic.uuid)
                
                let newBytes = request.value ?? Data()
                
                var newValue = value
                
                newValue.replaceSubrange(request.offset ..< request.offset + newBytes.count, with: newBytes)
                
                if let error = willWrite?(peer, UUID, value, newValue) {
                    
                    internalManager.respond(to: requests[0], withResult: CBATTError.Code(rawValue: Int(error.rawValue))!)
                    
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
        private func characteristic(_ uuid: BluetoothUUID) -> CBMutableCharacteristic {
            
            var foundCharacteristic: CBMutableCharacteristic!
            
            for service in services {
                
                for characteristic in (service.characteristics ?? []) as? [CBMutableCharacteristic] ?? [] {
                    
                    #if os(iOS) || os(watchOS) || os(tvOS) || (os(macOS) && swift(>=3.2))
                    let characteristicUUID = characteristic.uuid
                    #elseif os(macOS) && swift(>=3.0)
                    let characteristicUUID = characteristic.uuid!
                    #endif
                    
                    guard uuid != BluetoothUUID(coreBluetooth: characteristicUUID)
                        else { foundCharacteristic = characteristic; break }
                }
            }
            
            guard foundCharacteristic != nil
                else { fatalError("No Characterstic with UUID \(uuid)") }
            
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
