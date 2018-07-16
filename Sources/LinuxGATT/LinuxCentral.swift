//
//  LinuxCentral.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 1/22/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import Dispatch
import Bluetooth
import BluetoothLinux
import GATT

@available(OSX 10.12, *)
public final class LinuxCentral: CentralProtocol {
    
    public var log: ((String) -> ())?
    
    public let hostController: HostController
    
    public let maximumTransmissionUnit: ATTMaximumTransmissionUnit
    
    internal lazy var asyncQueue = DispatchQueue(label: "\(type(of: self)) Operation Queue")
    
    internal private(set) var scanData = [Peripheral: AdvertisingReport](minimumCapacity: 1)
    
    internal private(set) var connections = [Peripheral: Connection](minimumCapacity: 1)
    
    private var lastConnectionID = 0
    
    public init(hostController: HostController,
                maximumTransmissionUnit: ATTMaximumTransmissionUnit = .default) {
        
        self.hostController = hostController
        self.maximumTransmissionUnit = maximumTransmissionUnit
    }
    
    public func scan(filterDuplicates: Bool = true,
                     shouldContinueScanning: () -> (Bool),
                     foundDevice: @escaping (ScanData<Peripheral>) -> ()) throws {
        
        self.log?("Scanning...")
        
        try hostController.lowEnergyScan(filterDuplicates: filterDuplicates, shouldContinue: shouldContinueScanning) { [unowned self] (report) in
            
            let peripheral = Peripheral(identifier: report.address)
            
            let advertisement = AdvertisementData() // FIXME:
            
            let scanData = ScanData(peripheral: peripheral,
                                    date: Date(),
                                    rssi: Double(report.rssi.rawValue),
                                    advertisementData: advertisement)
            
            self.scanData[peripheral] = report
            
            foundDevice(scanData)
        }
        
        self.log?("Did discover \(self.scanData.count) peripherals")
    }
    
    public func connect(to peripheral: Peripheral, timeout: TimeInterval = .gattDefaultTimeout) throws {
        
        guard let advertisementData = scanData[peripheral]
            else { throw CentralError.unknownPeripheral }
        
        let socket = try async(timeout: timeout) {
            
            try L2CAPSocket.lowEnergyClient(
                destination: (address: advertisementData.address,
                              type: AddressType(lowEnergy: advertisementData.addressType)
                )
            )
        }
        
        // keep connection open and store for future use
        let connection = Connection(identifier: newConnectionID(),
                                    socket: socket,
                                    maximumTransmissionUnit: maximumTransmissionUnit)
        
        connection.log = { [weak self] in self?.log?($0) }
        
        connection.error = { [weak self] _ in
            self?.disconnect(peripheral: peripheral)
        }
        
        // store connection
        self.connections[peripheral] = connection
    }
    
    public func disconnect(peripheral: Peripheral) {
        
        self.connections[peripheral]?.stop()
        self.connections[peripheral] = nil
    }
    
    public func disconnectAll() {
        
        self.connections.values.forEach { $0.stop() }
        self.connections.removeAll(keepingCapacity: true)
    }
    
    public func discoverServices(_ services: [BluetoothUUID] = [],
                                 for peripheral: Peripheral,
                                 timeout: TimeInterval = .gattDefaultTimeout) throws -> [Service<Peripheral>] {
        
        return try connection(for: peripheral)
            .discoverServices(services, for: peripheral, timeout: timeout)
    }
    
    public func discoverCharacteristics(_ characteristics: [BluetoothUUID] = [],
                                        for service: Service<Peripheral>,
                                        timeout: TimeInterval = .gattDefaultTimeout) throws -> [Characteristic<Peripheral>] {
        
        return try connection(for: service.peripheral)
            .discoverCharacteristics(characteristics, for: service, timeout: timeout)
    }
    
    public func readValue(for characteristic: Characteristic<Peripheral>,
                          timeout: TimeInterval = .gattDefaultTimeout) throws -> Data {
        
        fatalError()
    }
    
    public func writeValue(_ data: Data,
                           for characteristic: Characteristic<Peripheral>,
                           withResponse: Bool = true,
                           timeout: TimeInterval = .gattDefaultTimeout) throws {
        
        fatalError()
    }
    
    public func notify(_ notification: ((Data) -> ())?,
                       for characteristic: Characteristic<Peripheral>,
                       timeout: TimeInterval = .gattDefaultTimeout) throws {
        
        fatalError()
    }
    
    // MARK: - Private Methods
    
    fileprivate func newConnectionID() -> Int {
        
        lastConnectionID += 1
        
        return lastConnectionID
    }
    
    private func connection(for peripheral: Peripheral) throws -> Connection {
        
        guard let _ = scanData[peripheral]
            else { throw CentralError.unknownPeripheral }
        
        guard let connection = connections[peripheral]
            else { throw CentralError.disconnected }
        
        return connection
    }
    
    private func async <T> (timeout: TimeInterval, _ operation: @escaping () throws -> (T)) throws -> (T) {
        
        var result: ErrorValue<T>?
        
        asyncQueue.async {
            
            do { result = .value(try operation()) }
            
            catch { result = .error(error) }
        }
        
        let endDate = Date() + timeout
        
        while Date() < endDate {
            
            guard let response = result
                else { usleep(100); continue }
            
            switch response {
            case let .error(error):
                throw error
            case let .value(value):
                return value
            }
        }
        
        // did timeout
        throw CentralError.timeout
    }
}

// MARK: - Supporting Types

@available(OSX 10.12, *)
public extension LinuxCentral {
    
    /// Peripheral Peer
    ///
    /// Represents a remote peripheral device that has been discovered.
    public struct Peripheral: Peer {
        
        public let identifier: Bluetooth.Address
        
        internal init(identifier: Bluetooth.Address) {
            
            self.identifier = identifier
        }
        
        fileprivate init(socket: BluetoothLinux.L2CAPSocket) {
            
            self.identifier = socket.address
        }
    }
}

@available(OSX 10.12, *)
internal extension LinuxCentral {
    
    internal typealias AdvertisingReport = HCILEAdvertisingReport.Report
}

@available(OSX 10.12, *)
internal extension LinuxCentral {
    
    final class Connection {
        
        let identifier: Int
        
        let peripheral: Peripheral
        
        let client: GATTClient
        
        var log: ((String) -> ())?
        
        var error: ((Error) -> ())?
        
        private(set) var isRunning = true
        
        private var thread: Thread?
        
        private var cache = Cache()
        
        init(identifier: Int,
             socket: L2CAPSocket,
             maximumTransmissionUnit: ATTMaximumTransmissionUnit) {
            
            self.identifier = identifier
            self.peripheral = Peripheral(socket: socket)
            self.client = GATTClient(socket: socket,
                                     maximumTransmissionUnit: maximumTransmissionUnit)
            
            // configure client
            client.log = { [unowned self] in self.log?("[\(self.client)]: " + $0) }
            
            // run socket in background
            start()
        }
        
        private func start() {
            
            self.isRunning = true
            
            let thread = Thread { [weak self] in self?.main() }
            thread.name = "LinuxCentral Connection \(identifier)"
            thread.start()
            
            self.thread = thread
        }
        
        func stop() {
            
            isRunning = false
            thread = nil
        }
        
        // MARK: - Private Methods
        
        private func main() {
            
            do {
                
                while isRunning {
                    
                    // write outgoing pending ATT PDUs (requests)
                    var didWrite = false
                    repeat { didWrite = try client.write() }
                    while didWrite
                    
                    // wait for incoming data (response, notifications, indications)
                    try client.read()
                }
            }
            
            catch {
                
                self.log?("[\(self.client)]: \(error)")
                self.error?(error)
                
                stop()
            }
        }
        
        private func async <T> (timeout: TimeInterval,
                                request: (@escaping ((GATTClientResponse<T>)) -> ()) -> ()) throws -> T {
            
            var result: GATTClientResponse<T>?
            
            request({ result = $0 })
            
            let endDate = Date() + timeout
            
            while Date() < endDate {
                
                guard let response = result
                    else { usleep(100); continue }
                
                switch response {
                case let .error(error):
                    throw error
                case let .value(value):
                    return value
                }
            }
            
            throw CentralError.timeout
        }
        
        // MARK: GATT Requests
        
        func discoverServices(_ services: [BluetoothUUID],
                              for peripheral: Peripheral,
                              timeout: TimeInterval) throws -> [Service<Peripheral>] {
            
            // GATT request
            let foundServices = try async(timeout: timeout) {
                client.discoverAllPrimaryServices(completion: $0)
            }
            
            // store in cache
            cache.insert(foundServices)
            
            return cache.services.map {
                Service(identifier: $0.key,
                        uuid: $0.value.attribute.uuid,
                        peripheral: peripheral,
                        isPrimary: $0.value.attribute.type == .primaryService)
            }
        }
        
        func discoverCharacteristics(_ characteristics: [BluetoothUUID],
                                     for service: Service<Peripheral>,
                                     timeout: TimeInterval) throws -> [Characteristic<Peripheral>] {
            
            assert(service.peripheral == peripheral)
            
            // get service
            guard let gattService = cache.service(for: service.identifier)?.attribute
                else { throw CentralError.invalidAttribute(service.uuid) }
            
            // GATT request
            let foundCharacteristics = try async(timeout: timeout) {
                client.discoverAllCharacteristics(of: gattService, completion: $0)
            }
            
            // store in cache
            cache.insert(foundCharacteristics, for: service.identifier)
            
            return cache.service(for: service.identifier)?.characteristics.map {
                Characteristic(identifier: $0.key,
                               uuid: $0.value.attribute.uuid,
                               peripheral: peripheral,
                               properties: $0.value.attribute.properties)
            } ?? []
        }
        
        func readValue(for characteristic: Characteristic<Peripheral>,
                       timeout: TimeInterval) throws -> Data {
            
            assert(characteristic.peripheral == peripheral)
            
            // GATT characteristic
            guard let (_ , gattCharacteristic) = cache.characteristic(for: characteristic.identifier)
                else { throw CentralError.invalidAttribute(characteristic.uuid) }
            
            // GATT request
            let value = try async(timeout: timeout) {
                client.readCharacteristic(gattCharacteristic.attribute, completion: $0)
            }
            
            return value
        }
        
        func writeValue(_ data: Data,
                        for characteristic: Characteristic<Peripheral>,
                        withResponse: Bool = true,
                        timeout: TimeInterval) throws {
            
            assert(characteristic.peripheral == peripheral)
            
            // GATT characteristic
            guard let (_ , gattCharacteristic) = cache.characteristic(for: characteristic.identifier)
                else { throw CentralError.invalidAttribute(characteristic.uuid) }
            
            // GATT request
            try async(timeout: timeout) {
                client.writeCharacteristic(gattCharacteristic.attribute,
                                           data: data,
                                           reliableWrites: withResponse,
                                           completion: $0)
            }
        }
        
        func discoverDescriptors(for characteristic: Characteristic<Peripheral>, timeout: TimeInterval) throws -> [Descriptor<Peripheral>] {
            
            assert(characteristic.peripheral == peripheral)
            
            // GATT characteristic
            guard let (gattService, gattCharacteristic) = cache.characteristic(for: characteristic.identifier)
                else { throw CentralError.invalidAttribute(characteristic.uuid) }
            
            let service = (declaration: gattService.attribute,
                           characteristics: Array(gattService.characteristics.values.map { $0.attribute }))
            
            // GATT request
            let foundDescriptors = try async(timeout: timeout) {
                client.discoverDescriptors(for: gattCharacteristic.attribute,
                                           service: service,
                                           completion: $0)
            }
            
            cache.insert(foundDescriptors, for: characteristic.identifier)
            
            return cache.characteristic(for: characteristic.identifier)?.1.descriptors.map {
                Descriptor(identifier: $0.key, uuid: $0.value.attribute.uuid, peripheral: peripheral)
            } ?? []
        }
        
        func notify(_ notification: ((Data) -> ())?,
                    for characteristic: Characteristic<Peripheral>,
                    timeout: TimeInterval) throws {
            
            assert(characteristic.peripheral == peripheral)
            
            // GATT characteristic
            guard let (_ , gattCharacteristic) = cache.characteristic(for: characteristic.identifier)
                else { throw CentralError.invalidAttribute(characteristic.uuid) }
            
            // Gatt Descriptors
            let descriptors: [GATTClient.Descriptor]
            
            if gattCharacteristic.descriptors.values.contains(where: { $0.attribute.uuid == .clientCharacteristicConfiguration }) {
                
                descriptors = Array(gattCharacteristic.descriptors.values.map { $0.attribute })
                
            } else {
                
                // fetch descriptors
                let _ = try discoverDescriptors(for: characteristic, timeout: timeout)
                
                // get updated cache
                if let cache = self.cache.characteristic(for: characteristic.identifier)?.1.descriptors.values.map({ $0.attribute }) {
                    
                    descriptors = Array(cache)
                    
                } else {
                    
                    descriptors = []
                }
            }
            
            // GATT request
            try async(timeout: timeout) {
                client.registerNotification(notification,
                                            for: gattCharacteristic.attribute,
                                            descriptors: descriptors,
                                            completion: $0)
            }
        }
    }
}

@available(OSX 10.12, *)
internal extension LinuxCentral.Connection {
    
    struct Cache {
        
        fileprivate init() { }
        
        private(set) var services = [UInt: ServiceCache](minimumCapacity: 1)
        
        func service(for identifier: UInt) -> ServiceCache? {
            
            return services[identifier]
        }
        
        func characteristic(for identifier: UInt) -> (ServiceCache, CharacteristicCache)? {
            
            for service in services.values {
                
                guard let characteristic = service.characteristics[identifier]
                    else { continue }
                
                return (service, characteristic)
            }
            
            return nil
        }
        
        func descriptor(for identifier: UInt) -> (ServiceCache, CharacteristicCache, DescriptorCache)? {
            
            for service in services.values {
                
                for characteristic in service.characteristics.values {
                    
                    for descriptor in characteristic.descriptors.values {
                        
                        return (service, characteristic, descriptor)
                    }
                }
            }
            
            return nil
        }
        
        mutating func insert(_ newValues: [GATTClient.Service]) {
            
            services.removeAll(keepingCapacity: true)
            
            newValues.forEach {
                let identifier = UInt($0.handle)
                services[identifier] = ServiceCache(attribute: $0, characteristics: [:])
            }
        }
        
        mutating func insert(_ newValues: [GATTClient.Characteristic],
                             for service: UInt) {
            
            // remove old values
            services[service]?.characteristics.removeAll(keepingCapacity: true)
            
            // insert new values
            newValues.forEach {
                services[service]?.characteristics[UInt($0.handle.declaration)] = CharacteristicCache(attribute: $0, notification: nil, descriptors: [:])
            }
        }
        
        mutating func insert(_ newValues: [GATTClient.Descriptor],
                             for characteristic: UInt) {
            
            var descriptorsCache = [UInt: DescriptorCache]()
            descriptorsCache.reserveCapacity(newValues.count)
            
            newValues.forEach {
                descriptorsCache[UInt($0.handle)] = DescriptorCache(attribute: $0)
            }
            
            for (serviceIdentifier, service) in services {
                
                guard let _ = service.characteristics[characteristic]
                    else { continue }
                
                services[serviceIdentifier]?.characteristics[characteristic]?.descriptors = descriptorsCache
            }
        }
    }
    
    struct ServiceCache {
        
        let attribute: GATTClient.Service
        
        var characteristics = [UInt: CharacteristicCache]()
    }
    
    struct CharacteristicCache {
        
        let attribute: GATTClient.Characteristic
        
        var notification: GATTClient.Notification?
        
        var descriptors = [UInt: DescriptorCache]()
    }
    
    struct DescriptorCache {
        
        let attribute: GATTClient.Descriptor
    }
}

/// Basic wrapper for error / value pairs.
private enum ErrorValue<T> {
    
    case error(Error)
    case value(T)
}

#if os(Linux)
    
/// The platform specific peripheral.
public typealias CentralManager = LinuxCentral
    
#endif
