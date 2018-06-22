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

// MARK: - Computed Properties

public extension CharacteristicManagedObject {
    
    public struct AttributesView {
        
        public typealias Property = GATT.CharacteristicProperty
        
        public var uuid: BluetoothUUID
        
        public var properties: BitMaskOptionSet<Property>
        
        public var value: Data?
    }
    
    public var attributesView: AttributesView {
        
        guard let uuid = BluetoothUUID(rawValue: self.uuid)
            else { fatalError("Invalid stored value \(self.uuid)") }
        
        let properties = BitMaskOptionSet<AttributesView.Property>(rawValue: UInt8(self.properties))
        
        return AttributesView(uuid: uuid,
                              properties: properties,
                              value: self.value)
    }
}

// MARK: - Fetch Requests

extension CharacteristicManagedObject {
    
    static func find(_ uuid: BluetoothUUID,
                     service: ServiceManagedObject,
                     in context: NSManagedObjectContext) throws -> CharacteristicManagedObject? {
        
        let entityName = self.entity(in: context).name!
        let fetchRequest = NSFetchRequest<CharacteristicManagedObject>(entityName: entityName)
        fetchRequest.predicate = NSPredicate(format: "%K == %@ && %K == %@",
                                             #keyPath(CharacteristicManagedObject.uuid),
                                             uuid.rawValue as NSString,
                                             #keyPath(CharacteristicManagedObject.service),
                                             service)
        fetchRequest.fetchLimit = 1
        fetchRequest.includesSubentities = false
        fetchRequest.returnsObjectsAsFaults = false
        
        return try context.fetch(fetchRequest).first
    }
    
    static func findOrCreate(_ uuid: BluetoothUUID,
                             service: ServiceManagedObject,
                             in context: NSManagedObjectContext) throws -> CharacteristicManagedObject {
        
        if let existing = try find(uuid, service: service, in: context) {
            
            return existing
            
        } else {
            
            // create a new entity
            let newManagedObject = CharacteristicManagedObject(context: context)
            
            // set identifier
            newManagedObject.uuid = uuid.rawValue
            newManagedObject.service = service
            
            return newManagedObject
        }
    }
}
