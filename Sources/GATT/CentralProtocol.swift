//
//  Central.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/3/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

#if canImport(Foundation)
import Foundation
#elseif canImport(SwiftFoundation)
import SwiftFoundation
#endif

#if canImport(Combine)
import Combine
#elseif canImport(OpenCombine)
import OpenCombine
#endif

#if canImport(Dispatch)
import Dispatch
#endif

import Bluetooth

/// GATT Central Manager
///
/// Implementation varies by operating system.
@available(*, deprecated, message: "Please migrate to 'CombineCentral'")
public typealias CentralProtocol = SynchronousCentral

// MARK: - Synchronous

/// GATT Central Manager
///
/// Implementation varies by operating system.
public protocol SynchronousCentral: class {
    
    associatedtype Peripheral: Peer
    
    associatedtype Advertisement: AdvertisementDataProtocol
    
    associatedtype AttributeID: Hashable
        
    var log: ((String) -> ())? { get set }
    
    /// Scans for peripherals that are advertising services.
    func scan(filterDuplicates: Bool,
              foundDevice: @escaping (ScanData<Peripheral, Advertisement>) -> ()) throws
    
    /// Stops scanning for peripherals.
    func stopScan()
    
    var isScanning: Bool { get }
    
    var scanningChanged: ((Bool) -> ())? { get set }
    
    func connect(to peripheral: Peripheral, timeout: TimeInterval) throws
    
    func disconnect(peripheral: Peripheral)
    
    func disconnectAll()
    
    var didDisconnect: ((Peripheral) -> ())? { get set }
    
    func discoverServices(_ services: [BluetoothUUID],
                          for peripheral: Peripheral,
                          timeout: TimeInterval) throws -> [Service<Peripheral, AttributeID>]
    
    func discoverCharacteristics(_ characteristics: [BluetoothUUID],
                                for service: Service<Peripheral, AttributeID>,
                                timeout: TimeInterval) throws -> [Characteristic<Peripheral, AttributeID>]
    
    func readValue(for characteristic: Characteristic<Peripheral, AttributeID>,
                   timeout: TimeInterval) throws -> Data
    
    func writeValue(_ data: Data,
                    for characteristic: Characteristic<Peripheral, AttributeID>,
                    withResponse: Bool,
                    timeout: TimeInterval) throws
    
    func notify(_ notification: ((Data) -> ())?,
                for characteristic: Characteristic<Peripheral, AttributeID>,
                timeout: TimeInterval) throws
    
    func maximumTransmissionUnit(for peripheral: Peripheral) throws -> ATTMaximumTransmissionUnit 
}

// MARK: - Asynchronous

/// Asyncronous GATT Central manager.
public protocol AsynchronousCentral: class {
    
    ///
    associatedtype Peripheral: Peer
    
    ///
    associatedtype Advertisement: AdvertisementDataProtocol
    
    ///
    associatedtype AttributeID: Hashable
    
    /// 
    var log: ((String) -> ())? { get set }
    
    /// Scans for peripherals that are advertising services.
    func scan(filterDuplicates: Bool,
              foundDevice: @escaping (ScanData<Peripheral, Advertisement>) -> ())
    
    /// Stops scanning for peripherals.
    func stopScan()
    
    ///
    var isScanning: Bool { get }
    
    ///
    var scanningChanged: ((Bool) -> ())? { get set }
    
    ///
    func connect(to peripheral: Peripheral,
                 timeout: TimeInterval,
                 completion: (Result<Void, Error>) -> ())
    
    ///
    func disconnect(peripheral: Peripheral)
    
    ///
    func disconnectAll()
    
    ///
    var didDisconnect: ((Peripheral) -> ())? { get set }
    
    ///
    func discoverServices(_ services: [BluetoothUUID],
                          for peripheral: Peripheral,
                          timeout: TimeInterval,
                          completion: (Result<[Service<Peripheral, AttributeID>], Error>) -> ())
    
    ///
    func discoverCharacteristics(_ characteristics: [BluetoothUUID],
                                for service: Service<Peripheral, AttributeID>,
                                timeout: TimeInterval,
                                completion: (Result<[Characteristic<Peripheral, AttributeID>], Error>) -> ())
    
    ///
    func readValue(for characteristic: Characteristic<Peripheral, AttributeID>,
                   timeout: TimeInterval,
                   completion: (Result<Data, Error>) -> ())
    
    ///
    func writeValue(_ data: Data,
                    for characteristic: Characteristic<Peripheral, AttributeID>,
                    withResponse: Bool,
                    timeout: TimeInterval,
                    completion: (Result<Void, Error>) -> ())
    
    ///
    func notify(_ notification: ((Data) -> ())?,
                for characteristic: Characteristic<Peripheral, AttributeID>,
                timeout: TimeInterval,
                completion: (Result<Void, Error>) -> ())
    
    ///
    func maximumTransmissionUnit(for peripheral: Peripheral,
                                 completion: (Result<ATTMaximumTransmissionUnit, Error>) -> ())
}
/*
// MARK: - Combine Support

#if canImport(Combine) || canImport(OpenCombine)

/// Asyncronous GATT Central manager.
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public final class CombineCentral <Central: SynchronousCentral> {
    
    public typealias Peripheral = Central.Peripheral
    
    public typealias Advertisement = Central.Advertisement
        
    public typealias AttributeID = Central.AttributeID
    
    public let central: Central
    
    public var userInfo = [String: Any]()
    
    public var queue = DispatchQueue(label: "\(Central.self) Combine Queue")
    
    public init(central: Central) {
        self.central = central
        self.isScanning = central.isScanning
        central.log = { [weak self] in self?.log.send($0) }
        central.scanningChanged = { [weak self] in self?.isScanning = $0 }
    }
    
    /// TODO: Improve logging API, use Logger?
    public let log = PassthroughSubject<String, Error>()
    
    @Published
    public private(set) var isScanning = false
    
    /// Scans for peripherals that are advertising services.
    func scan(filterDuplicates: Bool) -> PassthroughSubject<ScanData<Peripheral, Advertisement>, Error> {
        let subject = PassthroughSubject<ScanData<Peripheral, Advertisement>, Error>()
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                try self.central.scan(filterDuplicates: filterDuplicates, foundDevice)
            }
            catch {
                
            }
        }
        return subject
    }
    
    /// Stops scanning for peripherals.
    func stopScan()
    
    /// Connect to the specifed peripheral.
    func connect(to peripheral: Peripheral, timeout: TimeInterval) -> PassthroughSubject<Void, Error>
    
    /// Disconnect from the speciffied peripheral.
    func disconnect(peripheral: Peripheral)
    
    /// Disconnect from all connected peripherals.
    func disconnectAll()
    
    /// Notifies that a peripheral has been disconnected.
    var didDisconnect: PassthroughSubject<Peripheral, Error> { get }
    
    /// Discover the specified services.
    func discoverServices(_ services: [BluetoothUUID],
                          for peripheral: Peripheral,
                          timeout: TimeInterval) -> PassthroughSubject<Service<Peripheral>, Error>
    
    /// Discover characteristics for the specified service.
    func discoverCharacteristics(_ characteristics: [BluetoothUUID],
                                for service: Service<Peripheral>,
                                timeout: TimeInterval) -> PassthroughSubject<[Characteristic<Peripheral>], Error>
    
    /// Read characteristic value.
    func readValue(for characteristic: Characteristic<Peripheral>,
                   timeout: TimeInterval) -> PassthroughSubject<Data, Error>
    
    /// Write characteristic value.
    func writeValue(_ data: Data,
                    for characteristic: Characteristic<Peripheral>,
                    withResponse: Bool,
                    timeout: TimeInterval) -> PassthroughSubject<Void, Error>
    
    /// Subscribe to notifications for the specified characteristic.
    func notify(for characteristic: Characteristic<Peripheral>,
                timeout: TimeInterval) -> PassthroughSubject<Data, Error>
    
    /// Stop subcribing to notifications.
    func stopNotification(for characteristic: Characteristic<Peripheral>,
                          timeout: TimeInterval) -> PassthroughSubject<Void, Error>
    
    /// Get the maximum transmission unit for the specified peripheral.
    func maximumTransmissionUnit(for peripheral: Peripheral) -> PassthroughSubject<ATTMaximumTransmissionUnit, Error>
}

#endif
*/
// MARK: - Deprecated

#if !arch(wasm32) // && canImport(Dispatch)

public extension SynchronousCentral {
    
    func scan(duration: TimeInterval, filterDuplicates: Bool = true) throws -> [ScanData<Peripheral, Advertisement>] {
        
        let endDate = Date() + duration
        
        var results = [Peripheral: ScanData<Peripheral, Advertisement>](minimumCapacity: 1)
        
        try _scan(filterDuplicates: filterDuplicates,
                  shouldContinueScanning: { Date() < endDate },
                  foundDevice: { results[$0.peripheral] = $0 })
        
        return results.values.sorted(by: { $0.date < $1.date })
    }
    
    /// Scans for peripherals that are advertising services.
    @available(*, deprecated, message: "Use `stopScan()` instead")
    func scan(filterDuplicates: Bool = true,
              sleepDuration: TimeInterval = 1.0,
              shouldContinueScanning: @escaping () -> (Bool),
              foundDevice: @escaping (ScanData<Peripheral, Advertisement>) -> ()) throws {
        
        try _scan(filterDuplicates: filterDuplicates,
                  sleepDuration: sleepDuration,
                  shouldContinueScanning: shouldContinueScanning,
                  foundDevice: foundDevice)
    }
    
    internal func _scan(filterDuplicates: Bool = true,
                        sleepDuration: TimeInterval = 1.0,
                        shouldContinueScanning: @escaping () -> (Bool),
                        foundDevice: @escaping (ScanData<Peripheral, Advertisement>) -> ()) throws {
        
        var didThrow = false
        DispatchQueue.global().async { [weak self] in
            while shouldContinueScanning() {
                Thread.sleep(forTimeInterval: sleepDuration)
            }
            if didThrow == false {
                self?.stopScan()
            }
        }
        
        do { try self.scan(filterDuplicates: filterDuplicates, foundDevice: foundDevice) }
        catch {
            didThrow = true
            throw error
        }
    }
    
    /// Scans for peripherals that are advertising services for the specified time interval.
    func scan(duration: TimeInterval,
              filterDuplicates: Bool = true,
              foundDevice: @escaping (ScanData<Peripheral, Advertisement>) -> ()) throws {
        
        var didThrow = false
        DispatchQueue.global().asyncAfter(deadline: .now() + duration) { [weak self] in
            if didThrow == false {
                self?.stopScan()
            }
        }
        
        do { try scan(filterDuplicates: filterDuplicates, foundDevice: foundDevice) }
        catch {
            didThrow = true
            throw error
        }
    }
    
    /// Scans until a matching device is found or timeout.
    func scanFirst <Result> (timeout: TimeInterval = .gattDefaultTimeout,
                             filterDuplicates: Bool = true,
                             where filter: @escaping (ScanData<Peripheral, Advertisement>) -> Result?) throws -> Result {
        
        var value: Result?
        
        var didThrow = false
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
            if value == nil,
                didThrow == false {
                self?.stopScan()
            }
        }
        
        do {
            try self.scan(filterDuplicates: filterDuplicates) { [unowned self] (scanData) in
                guard let result = filter(scanData) else { return }
                value = result
                self.stopScan()
            }
        }
        catch {
            didThrow = true
            throw error
        }
        
        guard let result = value
            else { throw CentralError.timeout }
        
        return result
    }
    
    /// Scans until a matching device is found or timeout.
    func scanFirst(timeout: TimeInterval = .gattDefaultTimeout,
                   filterDuplicates: Bool = true,
                   where filter: @escaping (ScanData<Peripheral, Advertisement>) -> Bool) throws -> ScanData<Peripheral, Advertisement> {
        
        return try scanFirst(timeout: timeout, filterDuplicates: filterDuplicates) {
            filter($0) ? $0 : nil
        }
    }
}

#endif

// MARK: - Supporting Types

public protocol GATTAttribute: Hashable, Identifiable {
    
    associatedtype Peripheral: Peer
        
    var uuid: BluetoothUUID { get }
    
    var peripheral: Peripheral { get }
}

public struct Service <Peripheral: Peer, ID: Hashable> : GATTAttribute {
    
    public let id: ID
    
    public let uuid: BluetoothUUID
    
    public let peripheral: Peripheral
    
    public let isPrimary: Bool
    
    public init(id: ID,
                uuid: BluetoothUUID,
                peripheral: Peripheral,
                isPrimary: Bool = true) {
        
        self.id = id
        self.uuid = uuid
        self.peripheral = peripheral
        self.isPrimary = isPrimary
    }
}

public struct Characteristic <Peripheral: Peer, ID: Hashable> : GATTAttribute {
    
    public typealias Property = GATT.CharacteristicProperty
    
    public let id: ID
    
    public let uuid: BluetoothUUID
    
    public let peripheral: Peripheral
    
    public let properties: BitMaskOptionSet<Property>
    
    public init(id: ID,
                uuid: BluetoothUUID,
                peripheral: Peripheral,
                properties: BitMaskOptionSet<Property>) {
        
        self.id = id
        self.uuid = uuid
        self.peripheral = peripheral
        self.properties = properties
    }
}

public struct Descriptor <Peripheral: Peer, ID: Hashable>: GATTAttribute {
    
    public let id: ID
    
    public let uuid: BluetoothUUID
    
    public let peripheral: Peripheral
    
    public init(id: ID,
                uuid: BluetoothUUID,
                peripheral: Peripheral) {
        
        self.id = id
        self.uuid = uuid
        self.peripheral = peripheral
    }
}
