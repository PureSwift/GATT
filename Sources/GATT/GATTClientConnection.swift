//
//  GATTClientConnection.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 7/18/18.
//

#if swift(>=5.6) && canImport(BluetoothGATT)
import Foundation
import Bluetooth
import BluetoothGATT

@available(macOS 10.5, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
internal final class GATTClientConnection <Socket: L2CAPSocket> {
    
    // MARK: - Properties
    
    let peripheral: Peripheral
    
    private weak var delegate: GATTClientConnectionDelegate?
    
    let client: GATTClient
        
    private let cache = Cache()
    
    var maximumUpdateValueLength: Int {
        get async {
            // ATT_MTU-3
            return await Int(client.maximumTransmissionUnit.rawValue) - 3
        }
    }
    
    // MARK: - Initialization
    
    init(
        peripheral: Peripheral,
        socket: Socket,
        maximumTransmissionUnit: ATTMaximumTransmissionUnit,
        delegate: GATTClientConnectionDelegate
    ) async {
        self.peripheral = peripheral
        self.client = await GATTClient(
            socket: socket,
            maximumTransmissionUnit: maximumTransmissionUnit,
            log: { [weak delegate] message in
                delegate?.connection(peripheral, log: message)
            }, didDisconnect: { [weak delegate] error in
                await delegate?.connection(peripheral, didDisconnect: error)
            }
        )
    }
    
    // MARK: - Methods
    
    public func discoverServices(
        _ services: Set<BluetoothUUID>
    ) async throws -> [Service<Peripheral, UInt16>] {
        let foundServices = try await client.discoverAllPrimaryServices()
        await cache.insert(foundServices)
        return await cache.services.map {
            Service(
                id: $0.key,
                uuid: $0.value.attribute.uuid,
                peripheral: peripheral,
                isPrimary: $0.value.attribute.isPrimary
            )
        }
    }
    
    public func discoverCharacteristics(
        _ characteristics: Set<BluetoothUUID>,
        for service: Service<Peripheral, UInt16>
    ) async throws -> [Characteristic<Peripheral, UInt16>] {
        
        assert(service.peripheral == peripheral)
        
        // get service
        guard let gattService = await cache.service(for: service.id)?.attribute
            else { throw CentralError.invalidAttribute(service.uuid) }
        
        // GATT request
        let foundCharacteristics = try await self.client.discoverAllCharacteristics(of: gattService)
        
        // store in cache
        await cache.insert(foundCharacteristics, for: service.id)
        return await cache.service(for: service.id)?.characteristics.map {
            Characteristic(id: $0.key,
                           uuid: $0.value.attribute.uuid,
                           peripheral: peripheral,
                           properties: $0.value.attribute.properties)
        } ?? []
    }
    
    public func readValue(for characteristic: Characteristic<Peripheral, UInt16>) async throws -> Data {
        
        assert(characteristic.peripheral == peripheral)
        
        // GATT characteristic
        guard let (_ , gattCharacteristic) = await cache.characteristic(for: characteristic.id)
            else { throw CentralError.invalidAttribute(characteristic.uuid) }
        
        // GATT request
        return try await client.readCharacteristic(gattCharacteristic.attribute)
    }
    
    public func writeValue(
        _ data: Data,
        for characteristic: Characteristic<Peripheral, UInt16>,
        withResponse: Bool
    ) async throws {
        
        assert(characteristic.peripheral == peripheral)
        
        // GATT characteristic
        guard let (_ , gattCharacteristic) = await cache.characteristic(for: characteristic.id)
            else { throw CentralError.invalidAttribute(characteristic.uuid) }
        
        // GATT request
        try await client.writeCharacteristic(gattCharacteristic.attribute, data: data, withResponse: withResponse)
    }
    
    public func discoverDescriptors(
        for characteristic: Characteristic<Peripheral, UInt16>
    ) async throws -> [Descriptor<Peripheral, UInt16>] {
        
        assert(characteristic.peripheral == peripheral)
        
        // GATT characteristic
        guard let (gattService, gattCharacteristic) = await cache.characteristic(for: characteristic.id)
            else { throw CentralError.invalidAttribute(characteristic.uuid) }
        
        let service = (declaration: gattService.attribute,
                       characteristics: Array(gattService.characteristics.values.map { $0.attribute }))
        
        // GATT request
        let foundDescriptors = try await client.discoverDescriptors(of: gattCharacteristic.attribute, service: service)
        
        // update cache
        await cache.insert(foundDescriptors, for: characteristic.id)
        return await cache.characteristic(for: characteristic.id)?.1.descriptors.map {
            Descriptor(
                id: $0.key,
                uuid: $0.value.attribute.uuid,
                peripheral: peripheral
            )
        } ?? []
    }
    
    public func notify(
        _ characteristic: Characteristic<Peripheral, UInt16>,
        notification: (GATTClient.Notification)?
    ) async throws {
        
        assert(characteristic.peripheral == peripheral)
        
        // GATT characteristic
        guard let (_ , gattCharacteristic) = await cache.characteristic(for: characteristic.id)
            else { throw CentralError.invalidAttribute(characteristic.uuid) }
        
        // Gatt Descriptors
        let descriptors: [GATTClient.Descriptor]
        if gattCharacteristic.descriptors.values.contains(where: { $0.attribute.uuid == .clientCharacteristicConfiguration }) {
            descriptors = Array(gattCharacteristic.descriptors.values.map { $0.attribute })
        } else {
            // fetch descriptors
            let _ = try await self.discoverDescriptors(for: characteristic)
            // get updated cache
            if let cache = await cache.characteristic(for: characteristic.id)?.1.descriptors.values.map({ $0.attribute }) {
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
        try await client.clientCharacteristicConfiguration(
            gattCharacteristic.attribute,
            notification: notify,
            indication: indicate,
            descriptors: descriptors
        )
    }
    
    private func log(_ message: String) {
        delegate?.connection(peripheral, log: message)
    }
}

// MARK: - Supporting Types

internal protocol GATTClientConnectionDelegate: AnyObject {
    
    func connection(_ peripheral: Peripheral, log: String)
    
    func connection(_ peripheral: Peripheral, didDisconnect error: Swift.Error?) async
}

internal extension GATTClientConnection {
    
    typealias Cache = GATTClientConnectionCache
}

internal actor GATTClientConnectionCache {
    
    fileprivate init() { }
    
    private(set) var services = [UInt16: GATTClientConnectionServiceCache](minimumCapacity: 1)
    
    func service(for identifier: UInt16) -> GATTClientConnectionServiceCache? {
        return services[identifier]
    }
    
    func characteristic(for identifier: UInt16) -> (GATTClientConnectionServiceCache, GATTClientConnectionCharacteristicCache)? {
        
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
    
    func insert(_ newValues: [GATTClient.Service]) {
        services.removeAll(keepingCapacity: true)
        newValues.forEach {
            services[$0.handle] = GATTClientConnectionServiceCache(attribute: $0, characteristics: [:])
        }
    }
    
    func insert(
        _ newValues: [GATTClient.Characteristic],
        for service: UInt16
    ) {
        
        // remove old values
        services[service]?.characteristics.removeAll(keepingCapacity: true)
        // insert new values
        newValues.forEach {
            services[service]?.characteristics[$0.handle.declaration] = GATTClientConnectionCharacteristicCache(attribute: $0, notification: nil, descriptors: [:])
        }
    }
    
    func insert(_ newValues: [GATTClient.Descriptor],
                         for characteristic: UInt16) {
        
        var descriptorsCache = [UInt16: GATTClientConnectionDescriptorCache](minimumCapacity: newValues.count)
        newValues.forEach {
            descriptorsCache[$0.handle] = GATTClientConnectionDescriptorCache(attribute: $0)
        }
        for (serviceIdentifier, service) in services {
            guard let _ = service.characteristics[characteristic]
                else { continue }
            services[serviceIdentifier]?.characteristics[characteristic]?.descriptors = descriptorsCache
        }
    }
}

internal struct GATTClientConnectionServiceCache {
    
    let attribute: GATTClient.Service
    
    var characteristics = [UInt16: GATTClientConnectionCharacteristicCache]()
}

internal struct GATTClientConnectionCharacteristicCache {
    
    let attribute: GATTClient.Characteristic
    
    var notification: GATTClient.Notification?
    
    var descriptors = [UInt16: GATTClientConnectionDescriptorCache]()
}

internal struct GATTClientConnectionDescriptorCache {
    
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

