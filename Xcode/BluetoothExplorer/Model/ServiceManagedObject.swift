//
//  ServiceManagedObject.swift
//  BluetoothExplorer
//
//  Created by Alsey Coleman Miller on 6/18/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import CoreData
import Bluetooth
import GATT

/// CoreData managed object for discovered GATT Service.
public final class ServiceManagedObject: NSManagedObject {
    
    @NSManaged
    public var uuid: String
    
    @NSManaged
    public var isPrimary: Bool
    
    // MARK: - Relationships
    
    @NSManaged
    public var peripheral: PeripheralManagedObject
    
    @NSManaged
    public var characteristics: Set<CharacteristicManagedObject>
}

// MARK: - CoreData Encodable

public extension ServiceManagedObject {
    
    func update(_ value: CentralManager.Service) {
        
        self.uuid = value.uuid.rawValue
        self.isPrimary = value.isPrimary
    }
}

// MARK: - Fetch Requests

extension ServiceManagedObject {
    
    static func find(_ identifier: BluetoothUUID,
                     peripheral: Peripheral,
                     in context: NSManagedObjectContext) throws -> ServiceManagedObject? {
        
        let entityName = self.entity(in: context).name!
        let fetchRequest = NSFetchRequest<ServiceManagedObject>(entityName: entityName)
        fetchRequest.predicate = NSPredicate(format: "%K == %@ && %K == %@",
                                             #keyPath(ServiceManagedObject.uuid),
                                             identifier.rawValue as NSString,
                                             #keyPath(ServiceManagedObject.peripheral.identifier),
                                             peripheral.identifier.uuidString as NSString)
        fetchRequest.fetchLimit = 1
        fetchRequest.includesSubentities = false
        fetchRequest.returnsObjectsAsFaults = false
        
        return try context.fetch(fetchRequest).first
    }
    
    static func findOrCreate(_ identifier: BluetoothUUID,
                             peripheral: Peripheral,
                             in context: NSManagedObjectContext) throws -> ServiceManagedObject {
        
        if let existing = try find(identifier, peripheral: peripheral, in: context) {
            
            return existing
            
        } else {
            
            // create a new entity
            let newManagedObject = ServiceManagedObject(context: context)
            
            // set identifier
            newManagedObject.uuid = identifier.rawValue
            newManagedObject.peripheral = try PeripheralManagedObject.findOrCreate(peripheral.identifier,
                                                                                   in: context)
            
            return newManagedObject
        }
    }
}
