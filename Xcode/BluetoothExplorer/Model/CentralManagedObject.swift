//
//  CentralManagedObject.swift
//  BluetoothExplorer
//
//  Created by Alsey Coleman Miller on 6/15/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import CoreData

/// CoreData managed object for a Bluetooth Central Manager (should be a single instance).
public final class CentralManagedObject: NSManagedObject {
    
    // MARK: - Attributes
    
    @NSManaged
    public var identifier: String
    
    @NSManaged
    public var connectionTimeout: Double
    
    @NSManaged
    public var isScanning: Bool
    
    @NSManaged
    public var state: Int16
    
    // MARK: - Relationships
    
    @NSManaged
    public var foundDevices: Set<PeripheralManagedObject>
}
