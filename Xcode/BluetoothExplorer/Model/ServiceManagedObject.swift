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

// MARK: - Computed Properties

public extension ServiceManagedObject {
    
    public struct AttributesView {
        
        public var uuid: BluetoothUUID
        
        public var isPrimary: Bool
    }
    
    public var attributesView: AttributesView {
        
        guard let uuid = BluetoothUUID(rawValue: self.uuid)
            else { fatalError("Invalid stored value \(self.uuid)") }
        
        return AttributesView(uuid: uuid, isPrimary: self.isPrimary)
    }
}

// MARK: - CoreData Encodable

public extension ServiceManagedObject {
    
    func update(_ value: CentralManager.Service) {
        
        self.uuid = value.uuid.rawValue
        self.isPrimary = value.isPrimary
    }
}

// MARK: - CoreData Decodable

extension CentralManager.Service: CoreDataDecodable {
    
    public init(managedObject: ServiceManagedObject) {
        
        guard let uuid = BluetoothUUID(rawValue: managedObject.uuid)
            else { fatalError("Invalid value \(#keyPath(ServiceManagedObject.uuid)) \(managedObject.uuid)") }
        
        self.uuid = uuid
        self.isPrimary = managedObject.isPrimary
    }
}

// MARK: - Fetch Requests

extension ServiceManagedObject {
    
    static func find(_ uuid: BluetoothUUID,
                     peripheral: PeripheralManagedObject,
                     in context: NSManagedObjectContext) throws -> ServiceManagedObject? {
        
        let entityName = self.entity(in: context).name!
        let fetchRequest = NSFetchRequest<ServiceManagedObject>(entityName: entityName)
        fetchRequest.predicate = NSPredicate(format: "%K == %@ && %K == %@",
                                             #keyPath(ServiceManagedObject.uuid),
                                             uuid.rawValue as NSString,
                                             #keyPath(ServiceManagedObject.peripheral),
                                             peripheral)
        fetchRequest.fetchLimit = 1
        fetchRequest.includesSubentities = false
        fetchRequest.returnsObjectsAsFaults = false
        
        return try context.fetch(fetchRequest).first
    }
    
    static func findOrCreate(_ uuid: BluetoothUUID,
                             peripheral: PeripheralManagedObject,
                             in context: NSManagedObjectContext) throws -> ServiceManagedObject {
        
        if let existing = try find(uuid, peripheral: peripheral, in: context) {
            
            return existing
            
        } else {
            
            // create a new entity
            let newManagedObject = ServiceManagedObject(context: context)
            
            // set identifier
            newManagedObject.uuid = uuid.rawValue
            newManagedObject.peripheral = peripheral
            
            return newManagedObject
        }
    }
}
