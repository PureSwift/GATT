//
//  ScanEventManagedObject.swift
//  BluetoothExplorer
//
//  Created by Alsey Coleman Miller on 6/15/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import CoreData

/// CoreData managed object for a scan event. 
public final class ScanEventManagedObject: NSManagedObject {
    
    // MARK: - Attributes
    
    @NSManaged
    public var date: Date
    
    // MARK: - Properties
    
    @NSManaged
    public var peripheral: PeripheralManagedObject
}
