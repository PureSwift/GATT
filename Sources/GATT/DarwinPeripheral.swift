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

    public final class DarwinPeripheral: NSObject, PeripheralProtocol, CBPeripheralManagerDelegate {
        
        // MARK: - Properties
        
        public let options: Options
        
        public var log: ((String) -> ())?
        
        public var stateChanged: (DarwinBluetoothState) -> () = { _ in }
        
        public var state: DarwinBluetoothState {
            
            return unsafeBitCast(internalManager.state, to: DarwinBluetoothState.self)
        }
        
        public var willRead: ((_ central: Central, _ uuid: BluetoothUUID, _ handle: UInt16, _ value: Data, _ offset: Int) -> ATT.Error?)?
        
        public var willWrite: ((_ central: Central, _ uuid: BluetoothUUID, _ handle: UInt16, _ value: Data, _ newValue: Data) -> ATT.Error?)?
        
        public var didWrite: ((_ central: Central, _ uuid: BluetoothUUID, _ handle: UInt16, _ value: Data, _ newValue: Data) -> ())?
        
        // MARK: - Private Properties
        
        private lazy var internalManager: CBPeripheralManager = CBPeripheralManager(delegate: self, queue: self.queue, options: self.options.optionsDictionary)
        
        private lazy var queue: DispatchQueue = DispatchQueue(label: "\(type(of: self)) Internal Queue", attributes: [])
        
        private var addServiceState: (semaphore: DispatchSemaphore, error: Error?)?
        
        private var startAdvertisingState: (semaphore: DispatchSemaphore, error: Error?)?
        
        private var database = Database()
        
        // MARK: - Initialization
        
        public init(options: Options = Options()) {
            
            self.options = options
        }
        
        // MARK: - Methods
        
        public func start() throws {
            
            let options = AdvertisingOptions()
            
            try start(options: options)
        }
        
        public func start(options: AdvertisingOptions) throws {
            
            assert(startAdvertisingState == nil, "Already started advertising")
            
            let semaphore = DispatchSemaphore(value: 0)
            
            startAdvertisingState = (semaphore, nil) // set semaphore
            
            internalManager.startAdvertising(options.optionsDictionary)
            
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
        
        public func add(service: GATT.Service) throws -> UInt16 {
            
            assert(addServiceState == nil, "Already adding another Service")
            
            /// wait
            
            let semaphore = DispatchSemaphore(value: 0)
            
            addServiceState = (semaphore, nil) // set semaphore
            
            // add service
            let coreService = service.toCoreBluetooth()
            
            // CB add
            internalManager.add(coreService)
            
            let _ = semaphore.wait(timeout: .distantFuture)
            
            let error = addServiceState?.error
            
            // clear
            addServiceState = nil
            
            if let error = error {
                
                throw error
            }
            
            // DB cache add
            return database.add(service: service)
        }
        
        public func remove(service handle: UInt16) {
            
            // remove from daemon
            let coreService = database.service(for: handle)
            internalManager.remove(coreService)
            
            // remove from cache
            database.remove(service: handle)
        }
        
        public func clear() {
            
             // remove from daemon
            internalManager.removeAllServices()
            
            // clear cache
            database.clear()
        }
        
        // MARK: Subscript
        
        public subscript(characteristic uuid: BluetoothUUID) -> Data {
            
            get { return self[characteristic(uuid)] }
            
            set { internalManager.updateValue(newValue, for: characteristic(uuid), onSubscribedCentrals: nil) }
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
            
            let handle = request.characteristic.hashValue
            
            let uuid = BluetoothUUID(coreBluetooth: request.characteristic.uuid)
            
            guard request.offset <= value.count
                else { internalManager.respond(to: request, withResult: .invalidOffset); return }
            
            if let error = willRead?(peer, uuid, handle, value, request.offset) {
                
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
                
                let handle = request.characteristic.hashValue
                
                let uuid = BluetoothUUID(coreBluetooth: request.characteristic.uuid)
                
                let newBytes = request.value ?? Data()
                
                var newValue = value
                
                newValue.replaceSubrange(request.offset ..< request.offset + newBytes.count, with: newBytes)
                
                if let error = willWrite?(peer, uuid, handle, value, newValue) {
                    
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
        
        // MARK: Subscript
        
        private subscript(characteristic: CBCharacteristic) -> Data {
            
            get {
                
                for (service, characteristicValues) in database {
                    
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

// MARK: - Supporting Types

public extension DarwinPeripheral {
    
    public struct Options {
        
        public let showPowerAlert: Bool
        
        public let restoreIdentifier: String?
        
        public init(showPowerAlert: Bool = false,
                    restoreIdentifier: String? = nil) {
            
            self.showPowerAlert = showPowerAlert
            self.restoreIdentifier = restoreIdentifier
        }
        
        internal var optionsDictionary: [String: Any] {
            
            var options = [String: Any](minimumCapacity: 2)
            
            if showPowerAlert {
                
                options[CBPeripheralManagerOptionShowPowerAlertKey] = showPowerAlert as NSNumber
            }
            
            if let identifier = self.restoreIdentifier {
                
                options[CBPeripheralManagerOptionRestoreIdentifierKey] = identifier
            }
            
            return options
        }
    }
    
    public struct AdvertisingOptions {
        
        /// The local name of the peripheral.
        public let localName: String?
        
        /// An array of service UUIDs.
        public let serviceUUIDs: [BluetoothUUID]
        
        #if os(iOS)
        public let beacon: AppleBeacon?
        #endif
        
        #if os(iOS)
        public init(localName: String? = nil,
                    serviceUUIDs: [BluetoothUUID] = [],
                    beacon: AppleBeacon? = nil) {
            
            self.localName = localName
            self.beacon = beacon
            self.serviceUUIDs = serviceUUIDs
        }
        #else
        public init(localName: String? = nil,
                    serviceUUIDs: [BluetoothUUID] = []) {
            
            self.localName = localName
            self.serviceUUIDs = serviceUUIDs
        }
        #endif
        
        internal var optionsDictionary: [String: Any] {
            
            var options = [String: Any](minimumCapacity: 2)
            
            if let localName = self.localName {
                
                options[CBAdvertisementDataLocalNameKey] = localName
            }
            
            if serviceUUIDs.isEmpty == false {
                
                options[CBAdvertisementDataServiceUUIDsKey] = serviceUUIDs.map { $0.toCoreBluetooth() }
            }
            
            #if os(iOS)
            if let beacon = self.beacon {
                
                let beaconRegion = CLBeaconRegion(proximityUUID: beacon.uuid,
                                                  major: beacon.major,
                                                  minor: beacon.minor,
                                                  identifier: beacon.uuid.rawValue)
                
                let peripheralData = beaconRegion.peripheralData(withMeasuredPower: NSNumber(value: beacon.rssi))
                
                // copy key values
                peripheralData.forEach { (key, value) in
                    options[key as! String] = value
                }
            }
            #endif
            
            return options
        }
    }
}

private extension DarwinPeripheral {
    
    final class Database {
        
        private struct Service {
            
            var uuid: BluetoothUUID { return BluetoothUUID(coreBluetooth: attribute.uuid) }
            
            let handle: UInt16
            
            let attribute: CBMutableService
            
            let characteristics: [Characteristic]
        }
        
        private struct Characteristic {
            
            var uuid: BluetoothUUID { return BluetoothUUID(coreBluetooth: attribute.uuid) }
            
            let handle: UInt16
            
            let attribute: CBMutableCharacteristic
            
            var value: Data
        }
        
        @_versioned
        private var services = [UInt16: Service]()
        
        @_versioned
        private var characteristics = [UInt16: Characteristic]()
        
        /// Do not access directly, use `newHandle()`
        @_versioned
        iprivate var lastHandle: UInt16 = 0x0000
        
        private func newHandle() -> UInt16 {
            
            // starts at 0x0001
            lastHandle += 1
            
            return lastHandle
        }
        
        func add(service: GATT.Service) -> UInt16 {
            
            let coreService = service.toCoreBluetooth()
            
            let serviceHandle = newHandle()
            
            var characteristics = [Characteristic]()
            characteristics.reserveCapacity(coreService.characteristics?.count ?? 0)
            
            for (index, characteristic) in ((coreService.characteristics ?? []) as! [CBMutableCharacteristic]).enumerated()  {
                
                let data = service.characteristics[index].value
                
                let characteristicHandle = newHandle()
                
                characteristics.append(Characteristic(handle: characteristicHandle, attribute: characteristic, value: data))
            }
            
            self.services.append(Service(handle: serviceHandle, attribute: coreService, characteristics: characteristics))
            
            return serviceHandle
        }
        
        func remove(service handle: UInt16) {
            
            guard let index = services.index(where: { $0.handle == handle })
                else { assertionFailure("Invalid handle \(handle)"); return }
            
            services.remove(at: index)
        }
        
        func clear() {
            
            attributes.removeAll()
        }
        
        /// Find the service with the specified handle
        func service(for handle: UInt16) -> CBMutableService {
            
            guard let service = attributes[handle]
                else { fatalError("No service for handle \(handle)") }
            
            return service.attribute
        }
        
        /// Find the characteristic with the specified handle
        func characteristic(for handle: UInt16) -> CBMutableCharacteristic {
            
            for service in attributes.values {
                
                guard let characteristic = service.characteristics[handle]
                    else { continue }
                
                return characteristic.attribute
            }
            
            fatalError("No Characterstic for handle \(handle)")
        }
        
        subscript(characteristic uuid: BluetoothUUID) -> Data {
            
            get { return self[characteristic(uuid)] }
            
            set { internalManager.updateValue(newValue, for: characteristic(uuid), onSubscribedCentrals: nil) }
        }
        
        subscript(characteristic uuid: BluetoothUUID) -> Data {
            
            get { return self[characteristic(uuid)] }
            
            set { internalManager.updateValue(newValue, for: characteristic(uuid), onSubscribedCentrals: nil) }
        }
    }
}

#endif
