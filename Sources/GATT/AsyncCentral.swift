//
//  AsyncCentral.swift
//  
//
//  Created by Alsey Coleman Miller on 11/10/21.
//

#if swift(>=5.5)
import Foundation
import Bluetooth

@available(macOS 12, iOS 15.0, *)
public protocol AsyncCentral {
    
    /// Central Peripheral Type
    associatedtype Peripheral: Peer
    
    /// Central Advertisement Type
    associatedtype Advertisement: AdvertisementData
    
    /// Central Attribute ID (Handle)
    associatedtype AttributeID: Hashable
    
    ///
    var log: AsyncStream<String> { get }
     
    /// Scans for peripherals that are advertising services.
    func scan(filterDuplicates: Bool) -> AsyncThrowingStream<ScanData<Peripheral, Advertisement>, Error>
    
    /// Stops scanning for peripherals.
    func stopScan() async
    
    ///
    var isScanning: Bool { get }
    
    ///
    func connect(to peripheral: Peripheral,
                 timeout: TimeInterval) async throws
    
    ///
    func disconnect(_ peripheral: Peripheral) async
    
    ///
    func disconnectAll() async
    
    ///
    var didDisconnect: AsyncStream<Peripheral> { get }
    
    ///
    func discoverServices(
        _ services: [BluetoothUUID],
        for peripheral: Peripheral,
        timeout: TimeInterval
    ) -> AsyncThrowingStream<Service<Peripheral, AttributeID>, Error>
    
    ///
    func discoverCharacteristics(
        _ characteristics: [BluetoothUUID],
        for service: Service<Peripheral, AttributeID>,
        timeout: TimeInterval
    ) -> AsyncThrowingStream<Characteristic<Peripheral, AttributeID>, Error>
    
    ///
    func readValue(
        for characteristic: Characteristic<Peripheral, AttributeID>,
        timeout: TimeInterval
    ) async throws -> Data
    
    ///
    func writeValue(
        _ data: Data,
        for characteristic: Characteristic<Peripheral, AttributeID>,
        withResponse: Bool,
        timeout: TimeInterval
    ) async throws
    
    ///
    func notify(
        for characteristic: Characteristic<Peripheral, AttributeID>,
        timeout: TimeInterval
    ) -> AsyncThrowingStream<Data, Error>
    
    ///
    func maximumTransmissionUnit(for peripheral: Peripheral) async throws -> MaximumTransmissionUnit
}

@available(macOS 12.0, iOS 15.0, *)
public class AsyncCentralWrapper<Central: CentralProtocol>: AsyncCentral {
    
    public typealias Peripheral = Central.Peripheral
    
    public typealias Advertisement = Central.Advertisement
    
    public typealias AttributeID = Central.AttributeID
    
    internal let central: Central
    
    private var scanContinuation: AsyncThrowingStream<ScanData<Peripheral, Advertisement>, Error>.Continuation?
    
    private var notificationContinuation = [AttributeID: AsyncThrowingStream<Data, Error>.Continuation]()
    
    @usableFromInline
    internal init(_ central: Central) {
        self.central = central
    }
    
    ///
    public lazy var log = AsyncStream<String>.init { [weak self] continuation in
        self?.central.log = { continuation.yield($0) }
    }
     
    /// Scans for peripherals that are advertising services.
    public func scan(filterDuplicates: Bool) -> AsyncThrowingStream<ScanData<Peripheral, Advertisement>, Error> {
        // finish previous continuation
        if let continuation = scanContinuation {
            continuation.finish(throwing: nil)
            scanContinuation = nil
        }
        // return stream
        return AsyncThrowingStream(ScanData<Peripheral, Advertisement>.self, bufferingPolicy: .bufferingNewest(200)) { [unowned self] continuation in
            self.scanContinuation = continuation
            self.central.scan(filterDuplicates: filterDuplicates) { result in
                continuation.yield(with: result)
            }
        }
    }
    
    /// Stops scanning for peripherals.
    public func stopScan() async {
        self.central.stopScan()
        self.scanContinuation?.finish(throwing: nil)
    }
    
    ///
    public var isScanning: Bool {
        return central.isScanning
    }
    
    ///
    public func connect(to peripheral: Peripheral,
                        timeout: TimeInterval = .gattDefaultTimeout) async throws {
        try await withCheckedThrowingContinuation { [unowned self] continuation in
            self.central.connect(to: peripheral, timeout: timeout) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    ///
    public func disconnect(_ peripheral: Peripheral) async {
        self.central.disconnect(peripheral)
    }
    
    ///
    public func disconnectAll() async {
        central.disconnectAll()
    }
    
    ///
    public lazy var didDisconnect = AsyncStream<Peripheral>.init { [weak self] continuation in
        self?.central.didDisconnect = {
            continuation.yield($0)
        }
    }
    
    ///
    public func discoverServices(
        _ services: [BluetoothUUID] = [],
        for peripheral: Peripheral,
        timeout: TimeInterval = .gattDefaultTimeout
    ) -> AsyncThrowingStream<Service<Peripheral, AttributeID>, Error> {
        return AsyncThrowingStream<Service<Peripheral, AttributeID>, Error> { continuation in
            self.central.discoverServices(services, for: peripheral, timeout: timeout) { result in
                switch result {
                case let .success(values):
                    values.forEach {
                        continuation.yield($0)
                    }
                    continuation.finish(throwing: nil)
                case let .failure(error):
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    ///
    public func discoverCharacteristics(
        _ characteristics: [BluetoothUUID] = [],
        for service: Service<Peripheral, AttributeID>,
        timeout: TimeInterval = .gattDefaultTimeout
    ) -> AsyncThrowingStream<Characteristic<Peripheral, AttributeID>, Error> {
        return AsyncThrowingStream<Characteristic<Peripheral, AttributeID>, Error> { continuation in
            self.central.discoverCharacteristics(characteristics, for: service, timeout: timeout) { result in
                switch result {
                case let .success(values):
                    values.forEach {
                        continuation.yield($0)
                    }
                    continuation.finish(throwing: nil)
                case let .failure(error):
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    ///
    public func readValue(
        for characteristic: Characteristic<Peripheral, AttributeID>,
        timeout: TimeInterval = .gattDefaultTimeout
    ) async throws -> Data {
        return try await withCheckedThrowingContinuation { [unowned self] continuation in
            self.central.readValue(for: characteristic, timeout: timeout) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    ///
    public func writeValue(
        _ data: Data,
        for characteristic: Characteristic<Peripheral, AttributeID>,
        withResponse: Bool = true,
        timeout: TimeInterval = .gattDefaultTimeout
    ) async throws {
        try await withCheckedThrowingContinuation { [unowned self] continuation in
            self.central.writeValue(data, for: characteristic, withResponse: withResponse, timeout: timeout) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    ///
    public func notify(
        for characteristic: Characteristic<Peripheral, AttributeID>,
        timeout: TimeInterval = .gattDefaultTimeout
    ) -> AsyncThrowingStream<Data, Error> {
        // end previous stream
        if let continuation = self.notificationContinuation[characteristic.id] {
            continuation.finish(throwing: nil)
            self.notificationContinuation[characteristic.id] = nil
        }
        // return stream
        return AsyncThrowingStream<Data, Error> { [unowned self] continuation in
            self.notificationContinuation[characteristic.id] = continuation
            self.central.notify({ data in
                continuation.yield(data)
            }, for: characteristic, timeout: timeout) { result in
                switch result {
                case .success:
                    break
                case let .failure(error):
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    public func stopNotifications(
        for characteristic: Characteristic<Peripheral, AttributeID>,
        timeout: TimeInterval = .gattDefaultTimeout
    ) async throws {
        // end previous stream
        if let continuation = self.notificationContinuation[characteristic.id] {
            continuation.finish(throwing: nil)
            self.notificationContinuation[characteristic.id] = nil
        }
        // stop notifications
        try await withCheckedThrowingContinuation { [unowned self] continuation in
            self.central.notify(nil, for: characteristic, timeout: timeout) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    ///
    public func maximumTransmissionUnit(for peripheral: Peripheral) async throws -> MaximumTransmissionUnit {
        return try await withCheckedThrowingContinuation { [unowned self] continuation in
            self.central.maximumTransmissionUnit(for: peripheral) { result in
                continuation.resume(with: result)
            }
        }
    }
}
#endif
