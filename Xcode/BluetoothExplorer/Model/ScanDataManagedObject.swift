//
//  ScanEventManagedObject.swift
//  BluetoothExplorer
//
//  Created by Alsey Coleman Miller on 6/15/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import CoreData

/// CoreData managed object for a scan event. 
public final class ScanDataManagedObject: NSManagedObject {
    
    // MARK: - Attributes
    
    @NSManaged
    public var date: Date
    
    @NSManaged
    public var rssi: Int64
    
    // MARK: - Relationships
    
    @NSManaged
    public var peripheral: PeripheralManagedObject
    
    @NSManaged
    public var advertisementData: PeripheralManagedObject
    
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        
        self.date = Date()
        self.rssi = 0
    }
}

// MARK: - CoreData Encodable


