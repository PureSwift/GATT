//
//  SynchronousCentral.swift
//  
//
//  Created by Alsey Coleman Miller on 6/10/20.
//

#if !arch(wasm32) && (canImport(Foundation) || canImport(Dispatch))
import Foundation
import Dispatch
import Bluetooth

/// GATT Central Manager
///
/// Syncronous wrapper that blocks the current thread while performing operations.
public struct SynchronousCentral <Central: CentralProtocol> {
    
    public typealias Peripheral = Central.Peripheral
    
    public typealias Advertisement = Central.Advertisement
    
    public typealias AttributeID = Central.AttributeID
    
    // MARK: - Properties
    
    internal let central: Central
    
    public var log: ((String) -> ())? {
        get { return central.log }
        set { central.log = newValue }
    }
    
    public var isScanning: Bool {
        return central.isScanning
    }
    
    // MARK: - Initialization
    
    /// Initialize with the `CentralProtocol` object you want to wrap in a synchronous API.
    public init(_ central: Central) {
        self.central = central
    }
    
    // MARK: - Methods
    
    /// Scans for peripherals that are advertising services.
    ///
    /// - Note: Do not call on main thread, this method blocks until `stopScan()` is called.
    public func scan(filterDuplicates: Bool = true,
                     foundDevice: @escaping (ScanData<Peripheral, Advertisement>) -> ()) throws {
        
        // block while scanning
        let semaphore = Semaphore<Void>(timeout: Date.distantFuture.timeIntervalSinceNow)
        let oldScanningChanged = central.scanningChanged
        central.scanningChanged = { if $0 == false { semaphore.stopWaiting(.success(())) } }
        central.scan(filterDuplicates: filterDuplicates) { (result) in
            switch result {
            case let .failure(error):
                semaphore.stopWaiting(.failure(error))
            case let .success(scanData):
                foundDevice(scanData)
            }
        }
        try semaphore.wait()
        central.scanningChanged = oldScanningChanged
    }
    
    /// Stops scanning for peripherals.
    public func stopScan() {
        central.stopScan()
    }
    
    ///
    ///
    /// - Note: Do not call on main thread, this method blocks until `stopScan()` is called.
    public func connect(to peripheral: Peripheral, timeout: TimeInterval = .gattDefaultTimeout) throws {
        let semaphore = Semaphore<Void>(timeout: timeout)
        central.connect(to: peripheral, timeout: timeout, completion: semaphore.stopWaiting)
        try semaphore.wait()
    }
    
    public func disconnect(_ peripheral: Peripheral) {
        central.disconnect(peripheral)
    }
    
    public func disconnectAll() {
        central.disconnectAll()
    }
    
    public var didDisconnect: ((Peripheral) -> ())? {
        get { return central.didDisconnect }
        set { central.didDisconnect = newValue }
    }
    
    public func discoverServices(_ services: [BluetoothUUID],
                          for peripheral: Peripheral,
                          timeout: TimeInterval = .gattDefaultTimeout) throws -> [Service<Peripheral, AttributeID>] {
        
        let semaphore = Semaphore<[Service<Peripheral, AttributeID>]>(timeout: timeout)
        central.discoverServices(services, for: peripheral, timeout: timeout, completion: semaphore.stopWaiting)
        return try semaphore.wait()
    }
    
    public func discoverCharacteristics(_ characteristics: [BluetoothUUID],
                                        for service: Service<Peripheral, AttributeID>,
                                        timeout: TimeInterval = .gattDefaultTimeout) throws -> [Characteristic<Peripheral, AttributeID>] {
        
        let semaphore = Semaphore<[Characteristic<Peripheral, AttributeID>]>(timeout: timeout)
        central.discoverCharacteristics(characteristics, for: service, timeout: timeout, completion: semaphore.stopWaiting)
        return try semaphore.wait()
    }
    
    public func readValue(for characteristic: Characteristic<Peripheral, AttributeID>,
                          timeout: TimeInterval = .gattDefaultTimeout) throws -> Data {
        
        let semaphore = Semaphore<Data>(timeout: timeout)
        central.readValue(for: characteristic, timeout: timeout, completion: semaphore.stopWaiting)
        return try semaphore.wait()
    }
    
    public func writeValue(_ data: Data,
                           for characteristic: Characteristic<Peripheral, AttributeID>,
                           withResponse: Bool = true,
                           timeout: TimeInterval = .gattDefaultTimeout) throws {
        
        let semaphore = Semaphore<Void>(timeout: timeout)
        central.writeValue(data, for: characteristic, withResponse: withResponse, timeout: timeout, completion: semaphore.stopWaiting)
        try semaphore.wait()
    }
    
    public func notify(_ notification: ((Data) -> ())?,
                       for characteristic: Characteristic<Peripheral, AttributeID>,
                       timeout: TimeInterval = .gattDefaultTimeout) throws {
        
        let semaphore = Semaphore<Void>(timeout: timeout)
        central.notify(notification, for: characteristic, timeout: timeout, completion: semaphore.stopWaiting)
        try semaphore.wait()
    }
    
    public func maximumTransmissionUnit(for peripheral: Peripheral) throws -> MaximumTransmissionUnit {
        
        let semaphore = Semaphore<MaximumTransmissionUnit>(timeout: Date.distantFuture.timeIntervalSinceNow)
        central.maximumTransmissionUnit(for: peripheral, completion: semaphore.stopWaiting)
        return try semaphore.wait()
    }
}

internal extension CentralProtocol {
    
    @_alwaysEmitIntoClient
    var sync: SynchronousCentral<Self> {
        return SynchronousCentral(self)
    }
}

// MARK: - Deprecated

@available(*, deprecated, message: "Migrate to `SynchronousCentral`, completion blocks, await/async or Combine")
public extension CentralProtocol {
    
    func scan(duration: TimeInterval = .gattDefaultTimeout, filterDuplicates: Bool = true) throws -> [ScanData<Peripheral, Advertisement>] {
        return try sync.scan(duration: duration, filterDuplicates: filterDuplicates)
    }
    
    /// Scans for peripherals that are advertising services for the specified time interval.
    func scan(duration: TimeInterval = .gattDefaultTimeout,
              filterDuplicates: Bool = true,
              foundDevice: @escaping (ScanData<Peripheral, Advertisement>) -> ()) throws {
        try sync.scan(duration: duration, filterDuplicates: filterDuplicates, foundDevice: foundDevice)
    }
    
    func scan(filterDuplicates: Bool = true,
              foundDevice: @escaping (ScanData<Peripheral, Advertisement>) -> ()) throws {
        
        try sync.scan(filterDuplicates: filterDuplicates, foundDevice: foundDevice)
    }
    
    func connect(to peripheral: Peripheral, timeout: TimeInterval = .gattDefaultTimeout) throws {
        try sync.connect(to: peripheral, timeout: timeout)
    }
    
    func discoverServices(_ services: [BluetoothUUID] = [],
                          for peripheral: Peripheral,
                          timeout: TimeInterval = .gattDefaultTimeout) throws -> [Service<Peripheral, AttributeID>] {
        try sync.discoverServices(services, for: peripheral, timeout: timeout)
    }
    
    func discoverCharacteristics(_ characteristics: [BluetoothUUID] = [],
                                 for service: Service<Peripheral, AttributeID>,
                                 timeout: TimeInterval = .gattDefaultTimeout) throws -> [Characteristic<Peripheral, AttributeID>] {
        try sync.discoverCharacteristics(characteristics, for: service, timeout: timeout)
    }
    
    func readValue(for characteristic: Characteristic<Peripheral, AttributeID>,
                   timeout: TimeInterval = .gattDefaultTimeout) throws -> Data {
        try sync.readValue(for: characteristic, timeout: timeout)
    }
    
    func writeValue(_ data: Data,
                    for characteristic: Characteristic<Peripheral, AttributeID>,
                    withResponse: Bool = true,
                    timeout: TimeInterval = .gattDefaultTimeout) throws {
        try sync.writeValue(data, for: characteristic, withResponse: withResponse, timeout: timeout)
    }
    
    func notify(_ notification: ((Data) -> ())?,
                for characteristic: Characteristic<Peripheral, AttributeID>,
                timeout: TimeInterval = .gattDefaultTimeout) throws {
        try sync.notify(notification, for: characteristic, timeout: timeout)
    }
    
    func maximumTransmissionUnit(for peripheral: Peripheral) throws -> MaximumTransmissionUnit {
        try sync.maximumTransmissionUnit(for: peripheral)
    }
    
    func disconnect(peripheral: Peripheral) {
        disconnect(peripheral)
    }
}

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
        DispatchQueue.global().async { [weak central] in
            while shouldContinueScanning() {
                Thread.sleep(forTimeInterval: sleepDuration)
            }
            if didThrow == false {
                central?.stopScan()
            }
        }
        
        do { try central.sync.scan(filterDuplicates: filterDuplicates, foundDevice: foundDevice) }
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
        DispatchQueue.global().asyncAfter(deadline: .now() + duration) { [weak central] in
            if didThrow == false {
                central?.stopScan()
            }
        }
        
        do { try central.sync.scan(filterDuplicates: filterDuplicates, foundDevice: foundDevice) }
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
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak central] in
            if value == nil,
                didThrow == false {
                central?.stopScan()
            }
        }
        
        do {
            try central.sync.scan(filterDuplicates: filterDuplicates) { [unowned central] (scanData) in
                guard let result = filter(scanData) else { return }
                value = result
                central.stopScan()
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
