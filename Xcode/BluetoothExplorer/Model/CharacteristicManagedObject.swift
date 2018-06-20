//
//  CharacteristicManagedObject.swift
//  BluetoothExplorer
//
//  Created by Alsey Coleman Miller on 6/18/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import CoreData
import Bluetooth
import GATT

/// 
public final class CharacteristicManagedObject: NSManagedObject {
    
    // MARK: - Attributes
    
    @NSManaged
    public var uuid: String
    
    @NSManaged
    public var properties: Int16 // really `UInt8`
    
    @NSManaged
    public var value: Data?
    
    // MARK: - Relationships
    
    @NSManaged
    public var service: ServiceManagedObject
}

// MARK: - Fetch Requests

extension CharacteristicManagedObject {
    
    static func find(_ uuid: BluetoothUUID,
                     service: BluetoothUUID,
                     peripheral: Peripheral,
                     in context: NSManagedObjectContext) throws -> CharacteristicManagedObject? {
        
        let entityName = self.entity(in: context).name!
        let fetchRequest = NSFetchRequest<CharacteristicManagedObject>(entityName: entityName)
        fetchRequest.predicate = NSPredicate(format: "%K == %@ && %K == %@ && %K == %@",
                                             #keyPath(CharacteristicManagedObject.uuid),
                                             uuid.rawValue as NSString,
                                             #keyPath(CharacteristicManagedObject.service.uuid),
                                             service.rawValue as NSString,
                                             #keyPath(CharacteristicManagedObject.service.peripheral.identifier),
                                             peripheral.identifier.uuidString as NSString)
        fetchRequest.fetchLimit = 1
        fetchRequest.includesSubentities = false
        fetchRequest.returnsObjectsAsFaults = false
        
        return try context.fetch(fetchRequest).first
    }
    
    static func findOrCreate(_ uuid: BluetoothUUID,
                             service: BluetoothUUID,
                             peripheral: Peripheral,
                             in context: NSManagedObjectContext) throws -> CharacteristicManagedObject {
        
        if let existing = try find(uuid, service: service, peripheral: peripheral, in: context) {
            
            return existing
            
        } else {
            
            // create a new entity
            let newManagedObject = CharacteristicManagedObject(context: context)
            
            // set identifier
            newManagedObject.uuid = uuid.rawValue
            newManagedObject.service = try ServiceManagedObject.findOrCreate(service,
                                                                             peripheral: peripheral,
                                                                             in: context)
            
            return newManagedObject
        }
    }
}
