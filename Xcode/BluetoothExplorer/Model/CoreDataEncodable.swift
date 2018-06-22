//
//  CoreDataEncodable.swift
//  BluetoothExplorer
//
//  Created by Alsey Coleman Miller on 6/18/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import CoreData

/// Specifies how a type can be encoded to be stored with Core Data.
public protocol CoreDataEncodable {
    
    associatedtype ManagedObject: NSManagedObject
    
    func save(_ context: NSManagedObjectContext) throws -> ManagedObject
}

public extension Collection where Iterator.Element: CoreDataEncodable {
    
    func save(_ context: NSManagedObjectContext) throws -> Set<Self.Iterator.Element.ManagedObject> {
        
        var managedObjects = ContiguousArray<Iterator.Element.ManagedObject>()
        managedObjects.reserveCapacity(numericCast(self.count))
        
        for element in self {
            
            let managedObject = try element.save(context)
            
            managedObjects.append(managedObject)
        }
        
        return Set(managedObjects)
    }
}
