//
//  CharacteristicManagedObject.swift
//  BluetoothExplorer
//
//  Created by Alsey Coleman Miller on 6/18/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import CoreData

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
