//
//  DeviceManager.swift
//  BluetoothExplorer
//
//  Created by Alsey Coleman Miller on 6/15/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import CoreBluetooth
import Bluetooth
import GATT

/// Bluetooth Low Energy Device Manager GATT Client.
public final class DeviceManager {
    
    // MARK: - Initialization
    
    /// The default singleton `DeviceManager`.
    public static let shared = DeviceManager()
    
    // MARK: - Properties
    
    /// The log message handler.
    public var log: ((String) -> ())? {
        
        get { return internalManager.log }
        
        set { internalManager.log = newValue }
    }
    
    /// Whether the device manager is currently scanning for nearby devices.
    ///
    /// - Note: Observable property.
    public var isScanning = Observable(false)
    
    /// Connection timeout.
    public var connectionTimeout: Int = 30
    
    /// The found nearby devices.
    ///
    /// - Note: Observable property.
    public let foundDevices: Observable<[Peripheral: ScanResult]> = Observable([:])
    
    /// The current Bluetooth state of the device manager.
    ///
    /// - Note: Observable property.
    public lazy var state: Observable<BluetoothDarwinState> = Observable(self.internalManager.state)
    
    // MARK: - Private Properties
    
    private lazy var internalManager: CentralManager = {
        
        let central = CentralManager()
        
        // lazy initialization for CBCentralManager
        let _ = central.state
        
        central.stateChanged = { self.state.value = $0 }
        
        return central
    }()
    
    // MARK: - Subscripting
    
    /// Returns the cached device for the specified identifier.
    public subscript (identifier: Device.Identifier) -> Device? {
        
        get { return foundDevices.value[identifier]?.device }
    }
    
    // MARK: - Methods
    
    /// Scans for nearby devices.
    ///
    /// - Parameter duration: The duration of the scan.
    ///
    /// - Parameter event: Callback for a found device.
    public func scan(duration: TimeInterval, event: ((ScanResult) -> ())? = nil) throws {
        
        let start = Date()
        
        let end = start + duration
        
        try self.scan(event: event, scanMore: { Date() < end  })
    }
    
    /// Scans for nearby devices.
    ///
    /// - Parameter event: Callback for a found device.
    ///
    /// - Parameter scanMore: Callback for determining whether the manager
    /// should continue scanning for more devices.
    public func scan(event: ((ScanResult) -> ())? = nil, scanMore: () -> (Bool)) throws {
        
        guard isScanning.value == false
            else { assertionFailure("Already scanning"); return }
        
        assert(self.internalManager.state == .poweredOn, "Should only scan when powered on")
        
        log?("Scanning...")
        
        isScanning.value = true
        
        internalManager.disconnectAll()
        
        self.clear()
        
        self.internalManager.scan(shouldContinueScanning: scanMore) { [unowned self] (scanData) in
            
            event?(scanResult)
        }
        
        let foundDevicesCount = foundDevices.value.count
        
        if foundDevicesCount > 0 { self.log?("Found \(foundPeripheralsCount) peripherals") }
        
        isScanning.value = false
    }
    
    /// Clears the found devices cache.
    public func clear() {
        
        foundDevices.value.removeAll()
    }
    
    /// Disconnects (if connected) a specified device.
    ///
    /// - Parameter device: The device to disconnect.
    public func disconnect(device: Device) {
        
        internalManager.disconnect(peripheral: device.peripheral)
    }
}
