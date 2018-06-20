//
//  CoreDataExtensions.swift
//  BluetoothExplorer
//
//  Created by Alsey Coleman Miller on 6/15/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import CoreData

internal extension NSManagedObjectContext {
    
    /// Wraps the block to allow for error throwing.
    func performErrorBlockAndWait<Result>(_ block: @escaping () throws -> Result) throws -> Result {
        
        var blockError: Swift.Error?
        
        var result: Result!
        
        self.performAndWait {
            
            do { result = try block() }
                
            catch { blockError = error }
            
            return
        }
        
        if let error = blockError {
            
            throw error
        }
        
        return result
    }
    
    func find <T: NSManagedObject> (identifier: NSObject, property: String, entityName: String) throws -> T? {
        
        let fetchRequest = NSFetchRequest<T>(entityName: entityName)
        fetchRequest.predicate = NSPredicate(format: "%K == %@", property, identifier)
        fetchRequest.fetchLimit = 1
        fetchRequest.includesSubentities = true
        fetchRequest.returnsObjectsAsFaults = false
        
        return try self.fetch(fetchRequest).first
    }
    
    func findOrCreate <T: NSManagedObject> (identifier: NSObject, property: String, entityName: String) throws -> T {
        
        if let existing: T = try self.find(identifier: identifier, property: property, entityName: entityName) {
            
            return existing
            
        } else {
            
            // create a new entity
            let newManagedObject = NSEntityDescription.insertNewObject(forEntityName: entityName, into: self) as! T
            
            // set resource ID
            newManagedObject.setValue(identifier, forKey: property)
            
            return newManagedObject
        }
    }
}

internal extension NSManagedObject {
    
    static func entity(in context: NSManagedObjectContext) -> NSEntityDescription {
        
        let className = NSStringFromClass(self as AnyClass)
        
        struct Cache {
            static var entities = [String: NSEntityDescription]()
        }
        
        // try to get from cache
        if let entity = Cache.entities[className] {
            
            return entity
        }
        
        // search for entity with class name
        guard let entity = context.persistentStoreCoordinator?.managedObjectModel[self]
            else { fatalError("Could not find entity for \(type(of: self))") }
        
        Cache.entities[className] = entity
        
        return entity
    }
    
    convenience init(context: NSManagedObjectContext) {
        
        self.init(entity: type(of: self).entity(in: context), insertInto: context)
    }
}

extension NSManagedObjectModel {
    
    subscript(managedObjectType: NSManagedObject.Type) -> NSEntityDescription? {
        
        // search for entity with class name
        
        let className = NSStringFromClass(managedObjectType)
        
        return self.entities.first { $0.managedObjectClassName == className }
    }
}

public func NSFetchedResultsController <T: NSManagedObject>
    (_ managedObjectType: T.Type,
     delegate: NSFetchedResultsControllerDelegate? = nil,
     predicate: NSPredicate? = nil,
     sortDescriptors: [NSSortDescriptor] = [],
     sectionNameKeyPath: String? = nil,
     context: NSManagedObjectContext) -> NSFetchedResultsController<NSManagedObject> {
    
    let entity = context.persistentStoreCoordinator!.managedObjectModel[managedObjectType]!
    
    let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: entity.name!)
    
    fetchRequest.predicate = predicate
    
    fetchRequest.sortDescriptors = sortDescriptors
    
    let fetchedResultsController = CoreData.NSFetchedResultsController.init(fetchRequest: fetchRequest,
                                                                            managedObjectContext: context,
                                                                            sectionNameKeyPath: sectionNameKeyPath,
                                                                            cacheName: nil)
    
    fetchedResultsController.delegate = delegate
    
    return fetchedResultsController
}
