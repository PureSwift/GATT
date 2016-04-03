//
//  LinuxPeripheral.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/2/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import SwiftFoundation
import Bluetooth
import BluetoothLinux

#if os(Linux)
    /// The platform specific peripheral.
    public typealias Server = LinuxPeripheral
#endif

public final class LinuxPeripheral: PeripheralManager {
    
    // MARK: - Properties
    
    public var log: (String -> ())?
    
    public let maximumTransmissionUnit: Int
    
    // MARK: - Private Properties
    
    private var database = GATTDatabase()
    
    // MARK: - Initialization
    
    public init(maximumTransmissionUnit: Int = ATT.MTU.LowEnergy.Default) {
        
        self.maximumTransmissionUnit = maximumTransmissionUnit
    }
    
    // MARK: - Methods
    
    public func add(service: Service) throws -> Int {
        
        return database.add(service)
    }
    
    public func remove(service index: Int) {
        
        database.remove(service: index)
    }
    
    public func clear() {
        
        database.clear()
    }
    
    public func update(value: Data, forCharacteristic UUID: Bluetooth.UUID) {
        
        let matchingAttributes = database.attributes.filter({ $0.UUID == UUID })
        
        assert(matchingAttributes.count == 1, "\(matchingAttributes.count) Attributes with UUID \(UUID)")
        
        database.write(value, forAttribute: matchingAttributes[0].handle)
    }
}