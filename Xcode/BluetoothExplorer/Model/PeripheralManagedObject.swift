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
    public var isConnected: Bool
    
    // MARK: - Properties
    
    @NSManaged
    public var central: CentralManagedObject
    
    @NSManaged
    public var scanData: ScanDataManagedObject
    
    @NSManaged
    public var services: Set<ServiceManagedObject>
    
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        
        guard let context = self.managedObjectContext
            else { fatalError("Missing \(NSManagedObjectContext.self)") }
        
        self.scanData = ScanDataManagedObject(context: context)
    }
}

// MARK: - Computed Properties

public extension PeripheralManagedObject {
    
    public struct AttributesView {
        
        public var identifier: UUID
        
        public var isConnected: Bool
    }
    
    public var attributesView: AttributesView {
        
        guard let identifier = UUID(rawValue: self.identifier)
            else { fatalError("Invalid stored value \(self.identifier)") }
        
        return AttributesView(identifier: identifier, isConnected: self.isConnected)
    }
}

// MARK: - Fetch Requests

extension PeripheralManagedObject {
    
    static func find(_ identifier: UUID,
                     in context: NSManagedObjectContext) throws -> PeripheralManagedObject? {
        
        let identifier = identifier.uuidString as NSString
        
        let identifierProperty = #keyPath(PeripheralManagedObject.identifier)
        
        let entityName = self.entity(in: context).name!
        
        return try context.find(identifier: identifier, property: identifierProperty, entityName: entityName)
    }
    
    static func findOrCreate(_ identifier: UUID,
                             in context: NSManagedObjectContext) throws -> PeripheralManagedObject {
        
        let identifier = identifier.uuidString as NSString
        
        let identifierProperty = #keyPath(PeripheralManagedObject.identifier)
        
        let entityName = self.entity(in: context).name!
        
        return try context.findOrCreate(identifier: identifier, property: identifierProperty, entityName: entityName)
    }
}

// MARK: - CoreData Decodable
/*
public extension PeripheralModel {
    
    init(managedObject: PeripheralManagedObject) {
        
        self.identifier = UUID(uuidString: managedObject.identifier)!
        self.isConnected = managedObject.isConnected
        self.central = managedObject.central.identifier
        self.scanData = ScanData()
        self.services = services
    }
}
*/
