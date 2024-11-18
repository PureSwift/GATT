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
@preconcurrency import CoreBluetooth
import CoreLocation

public final class DarwinPeripheral: PeripheralManager, @unchecked Sendable {
    
    public typealias Error = Swift.Error
    
    // MARK: - Properties
    
    /// Logging
    public var log: (@Sendable (String) -> ())?
    
    public let options: Options
            
    public var state: DarwinBluetoothState {
        unsafeBitCast(self.peripheralManager.state, to: DarwinBluetoothState.self)
    }
    
    public var isAdvertising: Bool {
        self.peripheralManager.isAdvertising
    }
    
    public var willRead: ((GATTReadRequest<Central, Data>) -> ATTError?)?
    
    public var willWrite: ((GATTWriteRequest<Central, Data>) -> ATTError?)?
    
    public var didWrite: ((GATTWriteConfirmation<Central, Data>) -> ())?
    
    public var stateChanged: ((DarwinBluetoothState) -> ())?
    
    private var database = Database()
    
    private var peripheralManager: CBPeripheralManager!
    
    private var delegate: Delegate!
    
    private let queue: DispatchQueue = .main
    
    private var _continuation: Any?
    
    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    private var continuation: Continuation {
        get {
            _continuation as! Continuation
        }
        set {
            _continuation = newValue
        }
    }
    
    // MARK: - Initialization
    
    public init(
        options: Options = Options(showPowerAlert: false)
    ) {
        self.options = options
        let delegate = Delegate(self)
        let peripheralManager = CBPeripheralManager(
            delegate: delegate,
            queue: queue,
            options: options.options
        )
        self.delegate = delegate
        self.peripheralManager = peripheralManager
        if #available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *) {
            self.continuation = Continuation()
        }
    }
    
    // MARK: - Methods
    
    public func start() {
        let options = AdvertisingOptions()
        self.peripheralManager.startAdvertising(options.options)
    }
    
    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    public func start(options: AdvertisingOptions) async throws {
        return try await withCheckedThrowingContinuation { [unowned self] continuation in
            self.queue.async { [unowned self] in
                self.continuation.startAdvertising = continuation
                self.peripheralManager.startAdvertising(options.options)
            }
        }
    }
    
    public func stop() {
        peripheralManager.stopAdvertising()
    }
    
    public func add(service: GATTAttribute<Data>.Service) -> (UInt16, [UInt16]) {
        // add service
        let serviceObject = service.toCoreBluetooth()
        peripheralManager.add(serviceObject)
        let handle = database.add(service: service, serviceObject)
        return handle
    }
    
    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    public func add(service: GATTAttribute<Data>.Service) async throws -> (UInt16, [UInt16]) {
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
        let serviceObject = database.service(for: handle)
        peripheralManager.remove(serviceObject)
        // remove from cache
        database.remove(service: handle)
    }
    
    public func removeAllServices() {
        // remove from daemon
        peripheralManager.removeAllServices()
        // clear cache
        database.removeAll()
    }
    
    /// Modify the value of a characteristic, optionally emiting notifications if configured on active connections.
    public func write(_ newValue: Data, forCharacteristic handle: UInt16) {
        // update GATT DB
        database[characteristic: handle] = newValue
        // send notifications
        if #available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *) {
            Task {
                // attempt to write notifications
                var didNotify = updateValue(newValue, forCharacteristic: handle)
                while didNotify == false {
                    await waitPeripheralReadyUpdateSubcribers()
                    didNotify = updateValue(newValue, forCharacteristic: handle)
                }
            }
        } else {
            updateValue(newValue, forCharacteristic: handle)
        }
    }
    
    public func write(_ newValue: Data, forCharacteristic handle: UInt16, for central: Central) {
        write(newValue, forCharacteristic: handle) // per-connection database not supported on Darwin
    }
    
    public func value(for characteristicHandle: UInt16, central: Central) -> Data {
        self[characteristic: characteristicHandle]
    }
    
    /// Read the value of the characteristic with specified handle.
    public subscript(characteristic handle: UInt16) -> Data {
        self.database[characteristic: handle]
    }
    
    public subscript(characteristic handle: UInt16, central: Central) -> Data {
        self[characteristic: handle] // per-connection database not supported on Darwin
    }
    
    /// Return the handles of the characteristics matching the specified UUID.
    public func characteristics(for uuid: BluetoothUUID) -> [UInt16] {
        database.characteristics(for: uuid)
    }
    
    public func setDesiredConnectionLatency(_ latency: CBPeripheralManagerConnectionLatency, for central: Central) {
        guard let central = central.central else {
            assertionFailure()
            return
        }
        self.peripheralManager.setDesiredConnectionLatency(latency, for: central)
    }
    
    // MARK: - Private Methods
    
    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    private func waitPeripheralReadyUpdateSubcribers() async {
        await withCheckedContinuation { [unowned self] continuation in
            self.queue.async { [unowned self] in
                self.continuation.canNotify = continuation
            }
        }
    }
    
    @discardableResult
    private func updateValue(_ value: Data, forCharacteristic handle: UInt16, centrals: [Central] = []) -> Bool {
        let characteristicObject = database.characteristic(for: handle)
        // sends an updated characteristic value to one or more subscribed centrals, via a notification or indication.
        let didNotify = peripheralManager.updateValue(
            value,
            for: characteristicObject,
            onSubscribedCentrals: centrals.isEmpty ? nil : centrals.compactMap { $0.central }
        )
        
        // The underlying transmit queue is full
        if didNotify == false {
            // send later in `peripheralManagerIsReady(toUpdateSubscribers:)` method is invoked
            // when more space in the transmit queue becomes available.
            //log("Did queue notification for \((characteristic as CBCharacteristic).uuid)")
        } else {
            //log("Did send notification for \((characteristic as CBCharacteristic).uuid)")
        }
        return didNotify
    }
}

// MARK: - Supporting Types

public extension DarwinPeripheral {
    
    /// Peripheral Peer
    ///
    /// Represents a remote peripheral device that has been discovered.
    struct Central: Peer, Identifiable, Equatable, Hashable, CustomStringConvertible {
        
        public let id: UUID
        
        internal weak var central: CBCentral?
        
        init(_ central: CBCentral) {
            self.id = central.id
            self.central = central
        }
    }
}

public extension DarwinPeripheral {
    
    struct Options: Equatable, Hashable {
        
        internal let options: [String: NSObject]
        
        public init() {
            self.options = [:]
        }
    }
}

public extension DarwinPeripheral.Options {
    
    var showPowerAlert: Bool {
        (options[CBPeripheralManagerOptionShowPowerAlertKey] as? Bool) ?? false
    }
    
    var restoreIdentifier: String? {
        options[CBPeripheralManagerOptionRestoreIdentifierKey] as? String
    }
    
    init(
        showPowerAlert: Bool,
        restoreIdentifier: String? = Bundle.main.bundleIdentifier ?? "org.pureswift.GATT.DarwinPeripheral"
    ) {
        var options = [String: NSObject](minimumCapacity: 2)
        if showPowerAlert {
            options[CBPeripheralManagerOptionShowPowerAlertKey] = showPowerAlert as NSNumber
        }
        options[CBPeripheralManagerOptionRestoreIdentifierKey] = restoreIdentifier as NSString?
        self.options = options
    }
}

extension DarwinPeripheral.Options: ExpressibleByDictionaryLiteral {
    
    public init(dictionaryLiteral elements: (String, NSObject)...) {
        self.options = .init(uniqueKeysWithValues: elements)
    }
}

extension DarwinPeripheral.Options: CustomStringConvertible {
    
    public var description: String {
        return (options as NSDictionary).description
    }
}

public extension DarwinPeripheral {
    
    struct AdvertisingOptions: Equatable, Hashable, @unchecked Sendable {
        
        internal let options: [String: NSObject]
        
        public init() {
            self.options = [:]
        }
    }
}

extension DarwinPeripheral.AdvertisingOptions: ExpressibleByDictionaryLiteral {
    
    public init(dictionaryLiteral elements: (String, NSObject)...) {
        self.options = .init(uniqueKeysWithValues: elements)
    }
}

extension DarwinPeripheral.AdvertisingOptions: CustomStringConvertible {
    
    public var description: String {
        return (options as NSDictionary).description
    }
}

public extension DarwinPeripheral.AdvertisingOptions {
    
    /// The local name of the peripheral.
    var localName: String? {
        options[CBAdvertisementDataLocalNameKey] as? String
    }
    
    /// An array of service UUIDs.
    var serviceUUIDs: [BluetoothUUID] {
        (options[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.map { BluetoothUUID($0) } ?? []
    }
    
    init(
        localName: String? = nil,
        serviceUUIDs: [BluetoothUUID] = [],
        beacon: AppleBeacon? = nil
    ) {
        var options = [String: NSObject](minimumCapacity: 5)
        if let localName = localName {
            options[CBAdvertisementDataLocalNameKey] = localName as NSString
        }
        if serviceUUIDs.isEmpty == false {
            options[CBAdvertisementDataServiceUUIDsKey] = serviceUUIDs.map { CBUUID($0) } as NSArray
        }
        if #available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *), let beacon = beacon {
            let beaconRegion = CLBeaconRegion(
                uuid: beacon.uuid,
                major: beacon.major,
                minor: beacon.minor,
                identifier: beacon.uuid.uuidString
            )
            let peripheralData = beaconRegion.peripheralData(withMeasuredPower: NSNumber(value: beacon.rssi)) as! [String: NSObject]
            peripheralData.forEach { (key, value) in
                options[key] = value
            }
        }
        self.options = options
        assert(localName == self.localName)
        assert(serviceUUIDs == self.serviceUUIDs)
    }
}

internal extension DarwinPeripheral {
    
    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    struct Continuation {
        
        var startAdvertising: CheckedContinuation<(), Error>?
        
        var addService: CheckedContinuation<(), Error>?
        
        var canNotify: CheckedContinuation<(), Never>?
        
        fileprivate init() { }
    }
}

internal extension DarwinPeripheral {
    
    @preconcurrency
    @objc(DarwinPeripheralDelegate)
    final class Delegate: NSObject, CBPeripheralManagerDelegate, @unchecked Sendable {
        
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
            self.peripheral.stateChanged?(state)
        }
        
        @objc(peripheralManager:willRestoreState:)
        public func peripheralManager(_ peripheralManager: CBPeripheralManager, willRestoreState state: [String : Any]) {
            log("Will restore state \(state)")
        }
        
        @objc(peripheralManagerDidStartAdvertising:error:)
        public func peripheralManagerDidStartAdvertising(_ peripheralManager: CBPeripheralManager, error: Error?) {
            if let error = error {
                log("Could not advertise (\(error))")
                if #available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *) {
                    self.peripheral.continuation.startAdvertising?.resume(throwing: error)
                }
                
            } else {
                log("Did start advertising")
                if #available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *) {
                    self.peripheral.continuation.startAdvertising?.resume()
                }
            }
            if #available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *) {
                self.peripheral.continuation.startAdvertising = nil
            }
        }
        
        @objc(peripheralManager:didAddService:error:)
        public func peripheralManager(_ peripheralManager: CBPeripheralManager, didAdd service: CBService, error: Error?) {
            if let error = error {
                log("Could not add service \(service.uuid) (\(error))")
                if #available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *) {
                    self.peripheral.continuation.addService?.resume(throwing: error)
                }
            } else {
                log("Added service \(service.uuid)")
                if #available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *) {
                    self.peripheral.continuation.addService?.resume()
                }
            }
            if #available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *) {
                self.peripheral.continuation.addService = nil
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
            if let error = self.peripheral.willRead?(readRequest) {
                peripheralManager.respond(to: request, withResult: CBATTError.Code(rawValue: Int(error.rawValue))!)
                return
            }
            
            let requestedValue = request.offset == 0 ? value : Data(value.suffix(request.offset))
            request.value = requestedValue
            peripheralManager.respond(to: request, withResult: .success)
        }
        
        @objc(peripheralManager:didReceiveWriteRequests:)
        public func peripheralManager(_ peripheralManager: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
            
            log("Did receive write requests for \(requests.map { $0.characteristic.uuid })")
            assert(requests.isEmpty == false)
            
            guard let firstRequest = requests.first else {
                assertionFailure()
                return
            }
            
            let writeRequests: [GATTWriteRequest<Central, Data>] = requests.map { request in
                let peer = Central(request.central)
                let characteristic = self.peripheral.database[characteristic: request.characteristic]
                let value = characteristic.value
                let uuid = BluetoothUUID(request.characteristic.uuid)
                let newValue = request.value ?? Data()
                return GATTWriteRequest(
                    central: peer,
                    maximumUpdateValueLength: request.central.maximumUpdateValueLength,
                    uuid: uuid,
                    handle: characteristic.handle,
                    value: value,
                    newValue: newValue
                )
            }
            
            let process: () -> (CBATTError.Code) = { [unowned self] in
                
                // validate write requests
                for writeRequest in writeRequests {
                    
                    // check if write is possible
                    if let error = self.peripheral.willWrite?(writeRequest) {
                        guard let code = CBATTError.Code(rawValue: Int(error.rawValue)) else {
                            assertionFailure("Invalid CBATTError: \(error.rawValue)")
                            return CBATTError.Code.unlikelyError
                        }
                        return code
                    }
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
                    self.peripheral.didWrite?(confirmation)
                }
                
                return CBATTError.Code.success
            }
            
            let result = process()
            peripheralManager.respond(to: firstRequest, withResult: result)
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
            if #available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *) {
                self.peripheral.continuation.canNotify?.resume()
                self.peripheral.continuation.canNotify = nil
            }
        }
    }
}

private extension DarwinPeripheral {
    
    struct Database: Sendable {
        
        struct Service: Sendable {
            
            let handle: UInt16
        }
        
        struct Characteristic: Sendable {
            
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
        
        mutating func add(service: GATTAttribute<Data>.Service, _ coreService: CBMutableService) -> (UInt16, [UInt16]) {
            
            let serviceHandle = newHandle()
            var characteristicHandles = [UInt16]()
            characteristicHandles.reserveCapacity((coreService.characteristics ?? []).count)
            services[coreService] = Service(handle: serviceHandle)
            for (index, characteristic) in ((coreService.characteristics ?? []) as! [CBMutableCharacteristic]).enumerated()  {
                let data = service.characteristics[index].value
                let characteristicHandle = newHandle()
                characteristics[characteristic] = Characteristic(
                    handle: characteristicHandle,
                    serviceHandle: serviceHandle,
                    value: data
                )
                characteristicHandles.append(characteristicHandle)
            }
            return (serviceHandle, characteristicHandles)
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
