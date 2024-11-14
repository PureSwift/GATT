//
//  GATTClientConnection.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 7/18/18.
//

#if canImport(BluetoothGATT)
import Bluetooth
import BluetoothGATT

@available(macOS 10.5, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
internal actor GATTClientConnection <Socket: L2CAPConnection> where Socket: Sendable {
    
    typealias Data = Socket.Data
    
    // MARK: - Properties
    
    let peripheral: Peripheral
    
    let client: GATTClient<Socket>
    
    private var cache = Cache()
        
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
        log: (@Sendable (String) -> ())? = nil
    ) async {
        self.peripheral = peripheral
        self.client = await GATTClient(
            socket: socket,
            maximumTransmissionUnit: maximumTransmissionUnit,
            log: log
        )
    }
    
    // MARK: - Methods
    
    public func run() async throws {
        try await client.run()
    }
    
    public func discoverServices(
        _ services: Set<BluetoothUUID>
    ) async throws -> [Service<Peripheral, UInt16>] {
        let foundServices = try await client.discoverAllPrimaryServices()
        cache.insert(foundServices)
        return cache.services.map {
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
        guard let gattService = cache.service(for: service.id)?.attribute
            else { throw CentralError.invalidAttribute(service.uuid) }
        
        // GATT request
        let foundCharacteristics = try await self.client.discoverAllCharacteristics(of: gattService)
        
        // store in cache
        cache.insert(foundCharacteristics, for: service.id)
        return cache.service(for: service.id)?.characteristics.map {
            Characteristic(id: $0.key,
                           uuid: $0.value.attribute.uuid,
                           peripheral: peripheral,
                           properties: $0.value.attribute.properties)
        } ?? []
    }
    
    public func readValue(for characteristic: Characteristic<Peripheral, UInt16>) async throws -> Data {
        
        assert(characteristic.peripheral == peripheral)
        
        // GATT characteristic
        guard let (_ , gattCharacteristic) = cache.characteristic(for: characteristic.id)
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
        guard let (_ , gattCharacteristic) = cache.characteristic(for: characteristic.id)
            else { throw CentralError.invalidAttribute(characteristic.uuid) }
        
        // GATT request
        try await client.writeCharacteristic(gattCharacteristic.attribute, data: data, withResponse: withResponse)
    }
    
    public func discoverDescriptors(
        for characteristic: Characteristic<Peripheral, UInt16>
    ) async throws -> [Descriptor<Peripheral, UInt16>] {
        
        assert(characteristic.peripheral == peripheral)
        
        // GATT characteristic
        guard let (gattService, gattCharacteristic) = cache.characteristic(for: characteristic.id)
            else { throw CentralError.invalidAttribute(characteristic.uuid) }
        
        let service = (
            declaration: gattService.attribute,
            characteristics: gattService.characteristics
                .values
                .lazy
                .sorted { $0.attribute.handle.declaration < $1.attribute.handle.declaration }
                .map { $0.attribute }
        )
        
        // GATT request
        let foundDescriptors = try await client.discoverDescriptors(of: gattCharacteristic.attribute, service: service)
        
        // update cache
        cache.insert(foundDescriptors, for: characteristic.id)
        return foundDescriptors.map {
            Descriptor(
                id: $0.handle,
                uuid: $0.uuid,
                peripheral: characteristic.peripheral
            )
        }
    }
    
    public func readValue(for descriptor: Descriptor<Peripheral, UInt16>) async throws -> Data {
        assert(descriptor.peripheral == peripheral)
        guard let (_, _, gattDescriptor) = cache.descriptor(for: descriptor.id) else {
            throw CentralError.invalidAttribute(descriptor.uuid)
        }
        return try await client.readDescriptor(gattDescriptor.attribute)
    }
    
    public func writeValue(_ data: Data, for descriptor: Descriptor<Peripheral, UInt16>) async throws {
        assert(descriptor.peripheral == peripheral)
        guard let (_, _, gattDescriptor) = cache.descriptor(for: descriptor.id) else {
            throw CentralError.invalidAttribute(descriptor.uuid)
        }
        try await client.writeDescriptor(gattDescriptor.attribute, data: data)
    }
    
    public func notify(
        _ characteristic: Characteristic<Peripheral, UInt16>,
        notification: (GATTClient<Socket>.Notification)?
    ) async throws {
        
        assert(characteristic.peripheral == peripheral)
        
        // GATT characteristic
        guard let (_ , gattCharacteristic) = cache.characteristic(for: characteristic.id)
            else { throw CentralError.invalidAttribute(characteristic.uuid) }
        
        // Gatt Descriptors
        let descriptors: [GATTClient<Socket>.Descriptor]
        if gattCharacteristic.descriptors.values.contains(where: { $0.attribute.uuid == .clientCharacteristicConfiguration }) {
            descriptors = Array(gattCharacteristic.descriptors.values.map { $0.attribute })
        } else {
            // fetch descriptors
            let _ = try await self.discoverDescriptors(for: characteristic)
            // get updated cache
            if let cache = cache.characteristic(for: characteristic.id)?.1.descriptors.values.map({ $0.attribute }) {
                descriptors = Array(cache)
            } else {
                descriptors = []
            }
        }
        
        let notify: GATTClient<Socket>.Notification?
        let indicate: GATTClient<Socket>.Notification?
        
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
}

// MARK: - Supporting Types

internal extension GATTClientConnection {
    
    struct Cache {
        
        fileprivate init() { }
        
        private(set) var services = [UInt16: Cache.Service](minimumCapacity: 1)
    }
}

internal extension GATTClientConnection.Cache {
    
    func service(for identifier: UInt16) -> Service? {
        return services[identifier]
    }
    
    func characteristic(for identifier: UInt16) -> (Service, Characteristic)? {
        
        for service in services.values {
            guard let characteristic = service.characteristics[identifier]
                else { continue }
            return (service, characteristic)
        }
        
        return nil
    }
    
    func descriptor(for identifier: UInt16) -> (Service, Characteristic, Descriptor)? {
        
        for service in services.values {
            for characteristic in service.characteristics.values {
                guard let descriptor = characteristic.descriptors[identifier]
                    else { continue }
                return (service, characteristic, descriptor)
            }
        }
        
        return nil
    }
    
    mutating func insert(_ newValues: [GATTClient<Socket>.Service]) {
        services.removeAll(keepingCapacity: true)
        newValues.forEach {
            services[$0.handle] = Service(attribute: $0, characteristics: [:])
        }
    }
    
    mutating func insert(
        _ newValues: [GATTClient<Socket>.Characteristic],
        for service: UInt16
    ) {
        
        // remove old values
        services[service]?.characteristics.removeAll(keepingCapacity: true)
        // insert new values
        newValues.forEach {
            services[service]?.characteristics[$0.handle.declaration] = Characteristic(attribute: $0, notification: nil, descriptors: [:])
        }
    }
    
    mutating func insert(_ newValues: [GATTClient<Socket>.Descriptor],
                         for characteristic: UInt16) {
        
        var descriptorsCache = [UInt16: Descriptor](minimumCapacity: newValues.count)
        newValues.forEach {
            descriptorsCache[$0.handle] = Descriptor(attribute: $0)
        }
        for (serviceIdentifier, service) in services {
            guard let _ = service.characteristics[characteristic]
                else { continue }
            services[serviceIdentifier]?.characteristics[characteristic]?.descriptors = descriptorsCache
        }
    }
}

internal extension GATTClientConnection.Cache {
    
    struct Service {
        
        let attribute: GATTClient<Socket>.Service
        
        var characteristics = [UInt16: Characteristic]()
    }

    struct Characteristic {
        
        let attribute: GATTClient<Socket>.Characteristic
        
        var notification: GATTClient<Socket>.Notification?
        
        var descriptors = [UInt16: Descriptor]()
    }

    struct Descriptor {
        
        let attribute: GATTClient<Socket>.Descriptor
    }
}

#endif

