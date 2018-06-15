//
//  PeripheralManagedObject.swift
//  BluetoothExplorer
//
//  Created by Alsey Coleman Miller on 6/15/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import CoreData

/// CoreData managed object for a scanned Peripheral.
public final class PeripheralManagedObject: NSManagedObject {
    
    // MARK: - Attributes
    
    @NSManaged
    public var identifier: String
    
    @NSManaged
    public var name: String?
    
    // MARK: - Properties
    
    @NSManaged
    public var scanEvents: Set<ScanEventManagedObject>
}

// MARK: - Fetch Requests

extension PeripheralManagedObject {
    
    static func findOrCreate(_ identifier: UUID,
                             in context: NSManagedObjectContext) throws -> PeripheralManagedObject {
        
        let identifier = identifier.uuidString as NSString
        
        let identifierProperty = #keyPath(PeripheralManagedObject.identifier)
        
        let entityName = self.entity(in: context).name!
        
        return try context.findOrCreate(identifier: identifier, property: identifierProperty, entityName: entityName)
    }
}

// MARK: - CoreData Decodable

public extension PeripheralModel {
    
    init(managedObject: PeripheralManagedObject) {
        
        self.identifier = UUID(uuidString: managedObject.identifier)!
        self.name = managedObject.name
    }
}

