//
//  ServiceManagedObject.swift
//  BluetoothExplorer
//
//  Created by Alsey Coleman Miller on 6/18/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import CoreData

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
