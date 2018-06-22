//
//  CentralManagedObject.swift
//  BluetoothExplorer
//
//  Created by Alsey Coleman Miller on 6/15/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import CoreData

/// CoreData managed object for a Bluetooth Central Manager (should be a single instance).
public final class CentralManagedObject: NSManagedObject {
    
    // MARK: - Attributes
    
    @NSManaged
    public var identifier: String
    
    @NSManaged
    public var connectionTimeout: Double
    
    @NSManaged
    public var isScanning: Bool
    
    @NSManaged
    public var state: Int16
    
    // MARK: - Relationships
    
    @NSManaged
    public var foundDevices: Set<PeripheralManagedObject>
}

// MARK: - Fetch Requests

extension CentralManagedObject {
    
    static func findOrCreate(_ identifier: String,
                             in context: NSManagedObjectContext) throws -> CentralManagedObject {
        
        let identifier = identifier as NSString
        
        let identifierProperty = #keyPath(CentralManagedObject.identifier)
        
        let entityName = self.entity(in: context).name!
        
        return try context.findOrCreate(identifier: identifier, property: identifierProperty, entityName: entityName)
    }
}
