//
//  DarwinPeripheral.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/1/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

#if (os(macOS) || os(iOS)) && canImport(BluetoothGATT)
import Foundation
import Dispatch
import Bluetooth
import BluetoothGATT
import GATT
import CoreBluetooth
import CoreLocation

public final class DarwinPeripheral: PeripheralManager {
        
    // MARK: - Properties
    
    /// Logging
    public var log: ((String) -> ())?
    
    public let options: Options
            
    public var state: DarwinBluetoothState {
        get async {
            return await withUnsafeContinuation { [unowned self] continuation in
                self.queue.async { [unowned self] in
                    let state = unsafeBitCast(self.peripheralManager.state, to: DarwinBluetoothState.self)
                    continuation.resume(returning: state)
                }
            }
        }
    }
    
    public var willRead: ((GATTReadRequest<Central>) async -> ATTError?)?
    
    public var willWrite: ((GATTWriteRequest<Central>) async -> ATTError?)?
    
    public var didWrite: ((GATTWriteConfirmation<Central>) async -> ())?
    
    private var database = Database()
    
    private var peripheralManager: CBPeripheralManager!
    
    private var delegate: Delegate!
    
    private let queue = DispatchQueue(label: "org.pureswift.DarwinGATT.DarwinPeripheral", attributes: [])
    
    private var continuation = Continuation()
    
    // MARK: - Initialization
    
    public init(
        options: Options = Options()
    ) {
        self.options = options
        let delegate = Delegate(self)
        let peripheralManager = CBPeripheralManager(
            delegate: delegate,
            queue: queue,
            options: options.optionsDictionary
        )
        self.delegate = delegate
        self.peripheralManager = peripheralManager
    }
    
    // MARK: - Methods
    
    public func start() async throws {
        let options = AdvertisingOptions()
        try await start(options: options)
    }
    
    public func start(options: AdvertisingOptions) async throws {
        let options = options.optionsDictionary
        return try await withCheckedThrowingContinuation { [unowned self] continuation in
            self.queue.async { [unowned self] in
                self.continuation.startAdvertising = continuation
                self.peripheralManager.startAdvertising(options)
            }
        }
    }
    
    public func stop() {
        self.queue.async { [unowned self] in
            peripheralManager.stopAdvertising()
        }
    }
    
    public func add(service: GATTAttribute.Service) async throws -> UInt16 {
        let serviceObject = service.toCoreBluetooth()
        // add service
        try await withCheckedThrowingContinuation { [unowned self] (continuation: CheckedContinuation<(), Error>) in
            self.queue.async { [unowned self] in
                self.continuation.addService = continuation
                peripheralManager.add(serviceObject)
            }
        }
        // update DB
        return await withUnsafeContinuation { [unowned self] continuation in
            self.queue.async { [unowned self] in
                let handle = database.add(service: service, serviceObject)
                continuation.resume(returning: handle)
            }
        }
    }
    
    public func remove(service handle: UInt16) {
        self.queue.async { [unowned self] in
            // remove from daemon
            let serviceObject = database.service(for: handle)
            peripheralManager.remove(serviceObject)
            // remove from cache
            database.remove(service: handle)
        }
    }
    
    public func removeAllServices() {
        self.queue.async { [unowned self] in
            // remove from daemon
            peripheralManager.removeAllServices()
            // clear cache
            database.removeAll()
        }
    }
    
    /// Modify the value of a characteristic, optionally emiting notifications if configured on active connections.
    public func write(_ newValue: Data, forCharacteristic handle: UInt16) async {
        await withUnsafeContinuation { [unowned self] (continuation: UnsafeContinuation<(), Never>) in
            self.queue.async { [unowned self] in
                // update GATT DB
                database[characteristic: handle] = newValue
                continuation.resume()
            }
        }
        // send notifications
        await notify(newValue, forCharacteristic: handle)
    }
    
    /// Read the value of the characteristic with specified handle.
    public subscript(characteristic handle: UInt16) -> Data {
        get async {
            return await withUnsafeContinuation { [unowned self] continuation in
                self.queue.async { [unowned self] in
                    let value = self.database[characteristic: handle]
                    continuation.resume(returning: value)
                }
            }
        }
    }
    
    /// Return the handles of the characteristics matching the specified UUID.
    public func characteristics(for uuid: BluetoothUUID) async -> [UInt16] {
        return await withUnsafeContinuation { [unowned self] continuation in
            self.queue.async { [unowned self] in
                let handles = database.characteristics(for: uuid)
                continuation.resume(returning: handles)
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func notify(_ value: Data, forCharacteristic handle: UInt16) async {
        
        // attempt to write notifications
        var didNotify = await updateValue(value, forCharacteristic: handle)
        while didNotify == false {
            await waitPeripheralReadyUpdateSubcribers()
            didNotify = await updateValue(value, forCharacteristic: handle)
        }
    }
    
    private func waitPeripheralReadyUpdateSubcribers() async {
        await withCheckedContinuation { [unowned self] continuation in
            self.queue.async { [unowned self] in
                self.continuation.canNotify = continuation
            }
        }
    }
    
    private func updateValue(_ value: Data, forCharacteristic handle: UInt16) async -> Bool {
        return await withUnsafeContinuation { [unowned self] continuation in
            self.queue.async { [unowned self] in
                let characteristicObject = database.characteristic(for: handle)
                // sends an updated characteristic value to one or more subscribed centrals, via a notification or indication.
                let didNotify = peripheralManager.updateValue(
                    value,
                    for: characteristicObject,
                    onSubscribedCentrals: nil
                )
                
                // The underlying transmit queue is full
                if didNotify == false {
                    // send later in `peripheralManagerIsReady(toUpdateSubscribers:)` method is invoked
                    // when more space in the transmit queue becomes available.
                    //log("Did queue notification for \((characteristic as CBCharacteristic).uuid)")
                } else {
                    //log("Did send notification for \((characteristic as CBCharacteristic).uuid)")
                }
                
                continuation.resume(returning: didNotify)
            }
        }
    }
}

// MARK: - Supporting Types

public extension DarwinPeripheral {
    
    /// Peripheral Peer
    ///
    /// Represents a remote peripheral device that has been discovered.
    struct Central: Peer {
        
        public let id: UUID
        
        init(_ central: CBCentral) {
            self.id = central.id
        }
    }
}

public extension DarwinPeripheral {
    
    struct Options {
        
        public let showPowerAlert: Bool
        
        public let restoreIdentifier: String
        
        public init(
            showPowerAlert: Bool = false,
            restoreIdentifier: String = Bundle.main.bundleIdentifier ?? "org.pureswift.GATT.DarwinPeripheral"
        ) {
            self.showPowerAlert = showPowerAlert
            self.restoreIdentifier = restoreIdentifier
        }
        
        internal var optionsDictionary: [String: Any] {
            var options = [String: Any](minimumCapacity: 2)
            if showPowerAlert {
                options[CBPeripheralManagerOptionShowPowerAlertKey] = showPowerAlert as NSNumber
            }
            options[CBPeripheralManagerOptionRestoreIdentifierKey] = self.restoreIdentifier
            return options
        }
    }
    
    struct AdvertisingOptions {
        
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
                options[CBAdvertisementDataServiceUUIDsKey] = serviceUUIDs.map { CBUUID($0) }
            }
            
            #if os(iOS)
            if let beacon = self.beacon {
                
                let beaconRegion = CLBeaconRegion(
                    uuid: beacon.uuid,
                    major: beacon.major,
                    minor: beacon.minor,
                    identifier: beacon.uuid.uuidString
                )
                
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

internal extension DarwinPeripheral {
    
    struct Continuation {
        
        var startAdvertising: CheckedContinuation<(), Error>?
        
        var addService: CheckedContinuation<(), Error>?
        
        var canNotify: CheckedContinuation<(), Never>?
        
        fileprivate init() { }
    }
}

internal extension DarwinPeripheral {
    
    @objc(DarwinPeripheralDelegate)
    final class Delegate: NSObject, CBPeripheralManagerDelegate {
        
        unowned let peripheral: DarwinPeripheral
        
        init(_ peripheral: DarwinPeripheral) {
            self.peripheral = peripheral
        }
        
        private func log(_ message: String) {
            peripheral.log?(message)
        }
        
        // MARK: - CBPeripheralManagerDelegate
        
        @objc(peripheralManagerDidUpdateState:)
        public func peripheralManagerDidUpdateState(_ peripheralManager: CBPeripheralManager) {
            let state = unsafeBitCast(peripheralManager.state, to: DarwinBluetoothState.self)
            log("Did update state \(state)")
            //stateChanged(state)
        }
        
        @objc(peripheralManager:willRestoreState:)
        public func peripheralManager(_ peripheralManager: CBPeripheralManager, willRestoreState state: [String : Any]) {
            log("Will restore state \(state)")
        }
        
        @objc(peripheralManagerDidStartAdvertising:error:)
        public func peripheralManagerDidStartAdvertising(_ peripheralManager: CBPeripheralManager, error: Error?) {
            if let error = error {
                log("Could not advertise (\(error))")
                self.peripheral.continuation.startAdvertising?.resume(throwing: error)
            } else {
                log("Did start advertising")
                self.peripheral.continuation.startAdvertising?.resume()
            }
        }
        
        @objc(peripheralManager:didAddService:error:)
        public func peripheralManager(_ peripheralManager: CBPeripheralManager, didAdd service: CBService, error: Error?) {
            if let error = error {
                log("Could not add service \(service.uuid) (\(error))")
                self.peripheral.continuation.addService?.resume(throwing: error)
            } else {
                log("Added service \(service.uuid)")
                self.peripheral.continuation.addService?.resume()
            }
        }
        
        @objc(peripheralManager:didReceiveReadRequest:)
        public func peripheralManager(_ peripheralManager: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
            
            log("Did receive read request for \(request.characteristic.uuid)")
            
            let peer = Central(request.central)
            let characteristic = self.peripheral.database[characteristic: request.characteristic]
            let uuid = BluetoothUUID(request.characteristic.uuid)
            let value = characteristic.value
            let readRequest = GATTReadRequest(
                central: peer,
                maximumUpdateValueLength: request.central.maximumUpdateValueLength,
                uuid: uuid,
                handle: characteristic.handle,
                value: value,
                offset: request.offset
            )
            
            guard request.offset <= value.count else {
                peripheralManager.respond(to: request, withResult: .invalidOffset)
                return
            }
            
            Task {
                if let error = await self.peripheral.willRead?(readRequest) {
                    peripheral.queue.async {
                        peripheralManager.respond(to: request, withResult: CBATTError.Code(rawValue: Int(error.rawValue))!)
                    }
                    return
                }
                peripheral.queue.async {
                    let requestedValue = request.offset == 0 ? value : Data(value.suffix(request.offset))
                    request.value = requestedValue
                    peripheralManager.respond(to: request, withResult: .success)
                }
            }
        }
        
        @objc(peripheralManager:didReceiveWriteRequests:)
        public func peripheralManager(_ peripheralManager: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
            
            log("Did receive write requests for \(requests.map { $0.characteristic.uuid })")
            assert(requests.isEmpty == false)
            
            Task {
                var writeRequests = [GATTWriteRequest<Central>]()
                writeRequests.reserveCapacity(requests.count)
                // validate write requests
                for request in requests {
                    let peer = Central(request.central)
                    let characteristic = self.peripheral.database[characteristic: request.characteristic]
                    let value = characteristic.value
                    let uuid = BluetoothUUID(request.characteristic.uuid)
                    let newValue = request.value ?? Data()
                    let writeRequest = GATTWriteRequest(
                        central: peer,
                        maximumUpdateValueLength: request.central.maximumUpdateValueLength,
                        uuid: uuid,
                        handle: characteristic.handle,
                        value: value,
                        newValue: newValue
                    )
                    // check if write is possible
                    if let error = await self.peripheral.willWrite?(writeRequest) {
                        peripheral.queue.async {
                            peripheralManager.respond(to: requests[0], withResult: CBATTError.Code(rawValue: Int(error.rawValue))!)
                        }
                        return
                    }
                    // compute new data
                    writeRequests.append(writeRequest)
                }
                
                // write new values
                for request in writeRequests {
                    // update GATT DB
                    self.peripheral.database[characteristic: request.handle] = request.newValue
                    let confirmation = GATTWriteConfirmation(
                        central: request.central,
                        maximumUpdateValueLength: request.maximumUpdateValueLength,
                        uuid: request.uuid,
                        handle: request.handle,
                        value: request.newValue
                    )
                    // did write callback
                    await self.peripheral.didWrite?(confirmation)
                }
                
                peripheral.queue.async {
                    peripheralManager.respond(to: requests[0], withResult: .success)
                }
            }
        }
        
        @objc(peripheralManager:central:didSubscribeToCharacteristic:)
        public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
            log("Central \(central.id) did subscribe to \(characteristic.uuid)")
        }
        
        @objc
        public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
            log("Central \(central.id) did unsubscribe from \(characteristic.uuid)")
        }
        
        @objc
        public func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
            log("Ready to send notifications")
            self.peripheral.continuation.canNotify?.resume()
        }
    }
}

private extension DarwinPeripheral {
    
    struct Database {
        
        struct Service {
            
            let handle: UInt16
        }
        
        struct Characteristic {
            
            let handle: UInt16
            
            let serviceHandle: UInt16
            
            var value: Data
        }
        
        private var services = [CBMutableService: Service]()
        
        private var characteristics = [CBMutableCharacteristic: Characteristic]()
        
        /// Do not access directly, use `newHandle()`
        private var lastHandle: UInt16 = 0x0000
        
        /// Simulate a GATT database.
        private mutating func newHandle() -> UInt16 {
            
            assert(lastHandle != .max)
            
            // starts at 0x0001
            lastHandle += 1
            
            return lastHandle
        }
        
        mutating func add(service: GATTAttribute.Service, _ coreService: CBMutableService) -> UInt16 {
            
            let serviceHandle = newHandle()
            
            services[coreService] = Service(handle: serviceHandle)
            
            for (index, characteristic) in ((coreService.characteristics ?? []) as! [CBMutableCharacteristic]).enumerated()  {
                
                let data = service.characteristics[index].value
                
                let characteristicHandle = newHandle()
                
                characteristics[characteristic] = Characteristic(handle: characteristicHandle,
                                                                 serviceHandle: serviceHandle,
                                                                 value: data)
            }
            
            return serviceHandle
        }
        
        mutating func remove(service handle: UInt16) {
            
            let coreService = service(for: handle)
            
            // remove service
            services[coreService] = nil
            (coreService.characteristics as? [CBMutableCharacteristic])?.forEach { characteristics[$0] = nil }
            
            // remove characteristics
            while let index = characteristics.firstIndex(where: { $0.value.serviceHandle == handle }) {
                characteristics.remove(at: index)
            }
        }
        
        mutating func removeAll() {
            
            services.removeAll()
            characteristics.removeAll()
        }
        
        /// Find the service with the specified handle
        func service(for handle: UInt16) -> CBMutableService {
            
            guard let coreService = services.first(where: { $0.value.handle == handle })?.key
                else { fatalError("Invalid handle \(handle)") }
            
            return coreService
        }
        
        /// Return the handles of the characteristics matching the specified UUID.
        func characteristics(for uuid: BluetoothUUID) -> [UInt16] {
            
            let characteristicUUID = CBUUID(uuid)
            
            return characteristics
                .filter { $0.key.uuid == characteristicUUID }
                .map { $0.value.handle }
        }
        
        func characteristic(for handle: UInt16) -> CBMutableCharacteristic {
            
            guard let characteristic = characteristics.first(where: { $0.value.handle == handle })?.key
                else { fatalError("Invalid handle \(handle)") }
            
            return characteristic
        }
        
        subscript(characteristic handle: UInt16) -> Data {
            
            get {
                
                guard let value = characteristics.values.first(where: { $0.handle == handle })?.value
                    else { fatalError("Invalid handle \(handle)") }
                
                return value
            }
            
            set {
                
                guard let key = characteristics.first(where: { $0.value.handle == handle })?.key
                    else { fatalError("Invalid handle \(handle)") }
                
                characteristics[key]?.value = newValue
            }
        }
        
        subscript(characteristic uuid: BluetoothUUID) -> Data {
            
            get {
                
                let characteristicUUID = CBUUID(uuid)
                
                guard let characteristic = characteristics.first(where: { $0.key.uuid == characteristicUUID })?.value
                    else { fatalError("Invalid UUID \(uuid)") }
                
                return characteristic.value
            }
            
            set {
                
                let characteristicUUID = CBUUID(uuid)
                
                guard let key = characteristics.keys.first(where: { $0.uuid == characteristicUUID })
                    else { fatalError("Invalid UUID \(uuid)") }
                
                characteristics[key]?.value = newValue
            }
        }
        
        private(set) subscript(characteristic characteristic: CBCharacteristic) -> Characteristic {
            
            get {
                
                guard let key = characteristic as? CBMutableCharacteristic
                    else { fatalError("Invalid key") }
                
                guard let value = characteristics[key]
                    else { fatalError("No stored characteristic matches \(characteristic)") }
                
                return value
            }
            
            set {
                
                guard let key = characteristic as? CBMutableCharacteristic
                    else { fatalError("Invalid key") }
                
                characteristics[key] = newValue
            }
        }
        
        subscript(data characteristic: CBCharacteristic) -> Data {
            
            get {
                
                guard let key = characteristic as? CBMutableCharacteristic
                    else { fatalError("Invalid key") }
                
                guard let cache = characteristics[key]
                    else { fatalError("No stored characteristic matches \(characteristic)") }
                
                return cache.value
            }
            
            set { self[characteristic: characteristic].value = newValue }
        }
    }
}

#endif
