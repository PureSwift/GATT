//
//  AdvertisementDataManagedObject.swift
//  BluetoothExplorer
//
//  Created by Alsey Coleman Miller on 6/19/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import CoreData
import Bluetooth
import GATT

public final class AdvertisementDataManagedObject: NSManagedObject {
    
    // MARK: - Attributes
    
    @NSManaged
    public var isConnectable: NSNumber? // Bool
    
    @NSManaged
    public var localName: String?
    
    @NSManaged
    public var manufacturerData: Data?
    
    @NSManaged
    public var txPowerLevel: NSNumber? // Double
    
    // MARK: - Relationships
    
    @NSManaged
    public var scanData: ScanDataManagedObject
}

// MARK: - Encodable

public extension AdvertisementDataManagedObject {
    
    func update(_ value: AdvertisementData) {
        
        self.isConnectable = value.isConnectable as NSNumber?
        self.localName = value.localName
        self.manufacturerData = value.manufacturerData
        self.txPowerLevel = value.txPowerLevel as NSNumber?
    }
}

// MARK: - Decodable

extension AdvertisementData: CoreDataDecodable {
    
    public init(managedObject: AdvertisementDataManagedObject) {
        
        self.isConnectable = managedObject.isConnectable?.boolValue
        self.localName = managedObject.localName
        self.manufacturerData = managedObject.manufacturerData
        self.txPowerLevel = managedObject.txPowerLevel?.doubleValue
        
        // TODO: Implement other properties
        self.serviceData = [:]
        self.serviceUUIDs = []
        self.overflowServiceUUIDs = []
        self.solicitedServiceUUIDs = []
    }
}
