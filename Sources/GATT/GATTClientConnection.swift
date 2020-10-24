//
//  GATTClientConnection.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 7/18/18.
//

#if canImport(BluetoothGATT)
import Foundation
import Dispatch
import Bluetooth
import BluetoothGATT

@available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)
public final class GATTClientConnection <L2CAPSocket: L2CAPSocketProtocol> {
    
    // MARK: - Properties
    
    public let peripheral: Peripheral
    
    public let callback: GATTClientConnectionCallback
    
    internal let client: GATTClient
    
    private var error: Error?
    
    private var writePending: Bool = true
    
    private lazy var connectionThread: Thread = Thread { [weak self] in
        
        do {
            
            var didWrite = true
            var didRead = true
            
            // run until object is released
            while self != nil, self?.error == nil {
                
                // sleep if we did not previously read / write to save energy
                if didRead == false,
                    didWrite == false,
                    (self?.writePending ?? false) == false {
                    
                    // did not previously read or write, no pending writes
                    // sleep thread to save energy
                    usleep(100)
                }
                
                // attempt write
                didWrite = try self?.client.write() ?? false
                
                if didWrite {
                    self?.writePending = false
                }
                
                // attempt read
                didRead = try self?.client.read() ?? false
            }
        }
        
        catch { self?.disconnect(error) }
    }
    
    internal private(set) var cache = GATTClientConnectionCache()
    
    internal var maximumUpdateValueLength: Int {
        
        // ATT_MTU-3
        return Int(client.maximumTransmissionUnit.rawValue) - 3
    }
    
    // MARK: - Initialization
    
    deinit {
        
        self.callback.log?("[\(self.peripheral)]: Disconnected")
    }
    
    public init(peripheral: Peripheral,
                socket: L2CAPSocket,
                maximumTransmissionUnit: ATTMaximumTransmissionUnit,
                callback: GATTClientConnectionCallback) {
        
        self.peripheral = peripheral
        self.callback = callback
        self.client = GATTClient(socket: socket,
                                 maximumTransmissionUnit: maximumTransmissionUnit,
                                 log: { callback.log?("[\(peripheral)]: " + $0) },
                                 writePending: nil)
        
        // wakeup ATT writer
        self.client.writePending = { [weak self] in self?.writePending = true }
        
        // run read thread
        self.connectionThread.start()
    }
    
    // MARK: - Methods
    
    public func discoverServices(_ services: [BluetoothUUID],
                                 for peripheral: Peripheral,
                                 timeout: TimeInterval) throws -> [Service<Peripheral>] {
        
        // GATT request
        let foundServices = try async(timeout: timeout) {
            client.discoverAllPrimaryServices(completion: $0)
        }
        
        // store in cache
        cache.insert(foundServices)
        
        return cache.services.map {
            Service(
                identifier: $0.key,
                uuid: $0.value.attribute.uuid,
                peripheral: peripheral,
                isPrimary: $0.value.attribute.isPrimary
            )
        }
    }
    
    public func discoverCharacteristics(_ characteristics: [BluetoothUUID],
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
    
    public func readValue(for characteristic: Characteristic<Peripheral>,
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
    
    public func writeValue(_ data: Data,
                           for characteristic: Characteristic<Peripheral>,
                           withResponse: Bool = true,
                           timeout: TimeInterval) throws {
        
        assert(characteristic.peripheral == peripheral)
        
        // GATT characteristic
        guard let (_ , gattCharacteristic) = cache.characteristic(for: characteristic.identifier)
            else { throw CentralError.invalidAttribute(characteristic.uuid) }
        
        // GATT request
        try async(timeout: timeout) { (response: @escaping (GATTClientResponse<()>) -> ()) in
            
            let completion: ((GATTClientResponse<()>) -> ())? = withResponse ? response : nil
            
            client.writeCharacteristic(gattCharacteristic.attribute,
                                       data: data,
                                       reliableWrites: withResponse,
                                       completion: completion)
            
            // immediately call completion handler
            if completion == nil {
                response(.value(())) // success
            }
        }
    }
    
    public func discoverDescriptors(for characteristic: Characteristic<Peripheral>, timeout: TimeInterval) throws -> [Descriptor<Peripheral>] {
        
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
    
    public func notify(_ notification: ((Data) -> ())?,
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
        
        let notify: GATTClient.Notification?
        let indicate: GATTClient.Notification?
        
        /**
         If the specified characteristic is configured to allow both notifications and indications, calling this method enables notifications only. You can disable notifications and indications for a characteristic’s value by calling this method with the enabled parameter set to false.
         */
        
        if gattCharacteristic.attribute.properties.contains(.notify) {
            
            notify = notification
            indicate = nil
            
        } else if gattCharacteristic.attribute.properties.contains(.indicate) {
            
            notify = nil
            indicate = notification
            
        } else {
            
            notify = nil
            indicate = nil
            
            assertionFailure("Cannot enable notification or indication for characteristic \(characteristic.uuid)")
            return
        }
        
        // GATT request
        try async(timeout: timeout) {
            client.clientCharacteristicConfiguration(notification: notify,
                                                     indication: indicate,
                                                     for: gattCharacteristic.attribute,
                                                     descriptors: descriptors,
                                                     completion: $0)
        }
    }
    
    // MARK: - Private Methods
    
    // IO error
    private func disconnect(_ error: Error) {
        
        guard self.error == nil
            else { return }
        
        self.callback.log?("[\(self.peripheral)]: Error (\(error))")
        self.error = error
        self.callback.didDisconnect(error)
    }
    
    private func async <T> (timeout: TimeInterval,
                            request: (@escaping ((GATTClientResponse<T>)) -> ()) -> ()) throws -> T {
        
        var result: GATTClientResponse<T>?
        
        request({ result = $0 })
        
        let endDate = Date() + timeout
        
        while Date() < endDate {
            
            if let error = self.error {
                throw error
            }
            
            guard let response = result else {
                usleep(100)
                continue
            }
            
            switch response {
            case let .error(error):
                throw error
            case let .value(value):
                return value
            }
        }
        
        throw CentralError.timeout
    }
}

// MARK: - Supporting Types

public struct GATTClientConnectionCallback {
    
    public let log: ((String) -> ())?
    
    public let didDisconnect: ((Error) -> ())
    
    public init(log: ((String) -> ())? = nil,
                didDisconnect: @escaping ((Error) -> ())) {
        
        self.log = log
        self.didDisconnect = didDisconnect
    }
}

struct GATTClientConnectionCache {
    
    fileprivate init() { }
    
    private(set) var services = [UInt: GATTClientConnectionServiceCache](minimumCapacity: 1)
    
    func service(for identifier: UInt) -> GATTClientConnectionServiceCache? {
        
        return services[identifier]
    }
    
    func characteristic(for identifier: UInt) -> (GATTClientConnectionServiceCache, GATTClientConnectionCharacteristicCache)? {
        
        for service in services.values {
            
            guard let characteristic = service.characteristics[identifier]
                else { continue }
            
            return (service, characteristic)
        }
        
        return nil
    }
    
    func descriptor(for identifier: UInt) -> (GATTClientConnectionServiceCache, GATTClientConnectionCharacteristicCache, GATTClientConnectionDescriptorCache)? {
        
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
            services[identifier] = GATTClientConnectionServiceCache(attribute: $0, characteristics: [:])
        }
    }
    
    mutating func insert(_ newValues: [GATTClient.Characteristic],
                         for service: UInt) {
        
        // remove old values
        services[service]?.characteristics.removeAll(keepingCapacity: true)
        
        // insert new values
        newValues.forEach {
            services[service]?.characteristics[UInt($0.handle.declaration)] = GATTClientConnectionCharacteristicCache(attribute: $0, notification: nil, descriptors: [:])
        }
    }
    
    mutating func insert(_ newValues: [GATTClient.Descriptor],
                         for characteristic: UInt) {
        
        var descriptorsCache = [UInt: GATTClientConnectionDescriptorCache](minimumCapacity: newValues.count)
        
        newValues.forEach {
            descriptorsCache[UInt($0.handle)] = GATTClientConnectionDescriptorCache(attribute: $0)
        }
        
        for (serviceIdentifier, service) in services {
            
            guard let _ = service.characteristics[characteristic]
                else { continue }
            
            services[serviceIdentifier]?.characteristics[characteristic]?.descriptors = descriptorsCache
        }
    }
}

struct GATTClientConnectionServiceCache {
    
    let attribute: GATTClient.Service
    
    var characteristics = [UInt: GATTClientConnectionCharacteristicCache]()
}

struct GATTClientConnectionCharacteristicCache {
    
    let attribute: GATTClient.Characteristic
    
    var notification: GATTClient.Notification?
    
    var descriptors = [UInt: GATTClientConnectionDescriptorCache]()
}

struct GATTClientConnectionDescriptorCache {
    
    let attribute: GATTClient.Descriptor
}

internal extension CharacteristicProperty {
    
    init?(_ property: GATTCharacteristicProperty) {
        switch property {
        case .broadcast:
            self = .broadcast
        case .read:
            self = .read
        case .writeWithoutResponse:
            self = .writeWithoutResponse
        case .write:
            self = .write
        case .notify:
            self = .notify
        case .indicate:
            self = .indicate
        default:
            return nil
        }
    }
    
    static func from(_ properties: BitMaskOptionSet<GATTCharacteristicProperty>) -> Set<CharacteristicProperty> {
        
        var propertiesSet = Set<CharacteristicProperty>()
        propertiesSet.reserveCapacity(properties.count)
        properties
            .lazy
            .compactMap { CharacteristicProperty($0) }
            .forEach { propertiesSet.insert($0) }
        assert(propertiesSet.count == properties.count)
        return propertiesSet
    }
}

#endif
