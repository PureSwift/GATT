//
//  ScanEventManagedObject.swift
//  BluetoothExplorer
//
//  Created by Alsey Coleman Miller on 6/15/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import CoreData
import Bluetooth
import GATT

/// CoreData managed object for a scan event. 
public final class ScanDataManagedObject: NSManagedObject {
    
    // MARK: - Attributes
    
    @NSManaged
    public var date: Date
    
    @NSManaged
    public var rssi: Double
    
    // MARK: - Relationships
    
    @NSManaged
    public var peripheral: PeripheralManagedObject
    
    @NSManaged
    public var advertisementData: AdvertisementDataManagedObject
    
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        
        guard let context = self.managedObjectContext
            else { fatalError("Missing NSManagedObjectContext") }
        
        self.date = Date()
        self.advertisementData = AdvertisementDataManagedObject(context: context)
    }
}

// MARK: - CoreData Encodable

public extension ScanDataManagedObject {
    
    func update(_ value: ScanData) {
        
        self.date = value.date
        self.rssi = value.rssi
        self.advertisementData.update(value.advertisementData)
    }
}

// MARK: - CoreData Decodable

extension ScanData: CoreDataDecodable {
    
    public init(managedObject: ScanDataManagedObject) {
        
        guard let uuid = UUID(uuidString: managedObject.peripheral.identifier)
            else { fatalError("Invalid stored value") }
        
        self.date = managedObject.date
        self.rssi = managedObject.rssi
        self.peripheral = Peripheral(identifier: uuid)
        self.advertisementData = AdvertisementData(managedObject: managedObject.advertisementData)
    }
}
