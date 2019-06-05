//
//  Central.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/3/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import Foundation
import Bluetooth

/// GATT Central Manager
///
/// Implementation varies by operating system.
public protocol CentralProtocol: class {
    
    associatedtype Peripheral: Peer
    
    associatedtype Advertisement: AdvertisementDataProtocol
    
    var log: ((String) -> ())? { get set }
    
    /// Scans for peripherals that are advertising services.
    func scan(filterDuplicates: Bool,
              foundDevice: @escaping (ScanData<Peripheral, Advertisement>) -> ()) throws
    
    /// Stops scanning for peripherals.
    func stopScan()
    
    var isScanning: Bool { get }
    
    func connect(to peripheral: Peripheral, timeout: TimeInterval) throws
    
    func disconnect(peripheral: Peripheral)
    
    func disconnectAll()
    
    var didDisconnect: ((Peripheral) -> ())? { get set }
    
    func discoverServices(_ services: [BluetoothUUID],
                          for peripheral: Peripheral,
                          timeout: TimeInterval) throws -> [Service<Peripheral>]
    
    func discoverCharacteristics(_ characteristics: [BluetoothUUID],
                                for service: Service<Peripheral>,
                                timeout: TimeInterval) throws -> [Characteristic<Peripheral>]
    
    func readValue(for characteristic: Characteristic<Peripheral>,
                   timeout: TimeInterval) throws -> Data
    
    func writeValue(_ data: Data,
                    for characteristic: Characteristic<Peripheral>,
                    withResponse: Bool,
                    timeout: TimeInterval) throws
    
    func notify(_ notification: ((Data) -> ())?,
                for characteristic: Characteristic<Peripheral>,
                timeout: TimeInterval) throws
    
    func maximumTransmissionUnit(for peripheral: Peripheral) throws -> ATTMaximumTransmissionUnit 
}

public extension CentralProtocol {
    
    /// Scans for peripherals that are advertising services.
    @available(*, deprecated, message: "Use `stopScan()` instead")
    func scan(filterDuplicates: Bool = true,
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
    
// MARK: - Supporting Types

public protocol GATTAttribute {
    
    associatedtype Peripheral: Peer
    
    var identifier: UInt { get }
    
    var uuid: BluetoothUUID { get }
    
    var peripheral: Peripheral { get }
}

public struct Service <Peripheral: Peer> : GATTAttribute {
    
    public let identifier: UInt
    
    public let uuid: BluetoothUUID
    
    public let peripheral: Peripheral
    
    public let isPrimary: Bool
    
    public init(identifier: UInt,
                uuid: BluetoothUUID,
                peripheral: Peripheral,
                isPrimary: Bool = true) {
        
        self.identifier = identifier
        self.uuid = uuid
        self.peripheral = peripheral
        self.isPrimary = isPrimary
    }
}

public struct Characteristic <Peripheral: Peer> : GATTAttribute {
    
    public typealias Property = GATT.CharacteristicProperty
    
    public let identifier: UInt
    
    public let uuid: BluetoothUUID
    
    public let peripheral: Peripheral
    
    public let properties: BitMaskOptionSet<Property>
    
    public init(identifier: UInt,
                uuid: BluetoothUUID,
                peripheral: Peripheral,
                properties: BitMaskOptionSet<Property>) {
        
        self.identifier = identifier
        self.uuid = uuid
        self.peripheral = peripheral
        self.properties = properties
    }
}

public struct Descriptor <Peripheral: Peer>: GATTAttribute {
    
    public let identifier: UInt
    
    public let uuid: BluetoothUUID
    
    public let peripheral: Peripheral
    
    public init(identifier: UInt,
                uuid: BluetoothUUID,
                peripheral: Peripheral) {
        
        self.identifier = identifier
        self.uuid = uuid
        self.peripheral = peripheral
    }
}
