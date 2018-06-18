//
//  PeripheralModel.swift
//  BluetoothExplorer
//
//  Created by Alsey Coleman Miller on 6/15/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import GATT

public struct PeripheralModel {
    
    // MARK: - Attributes
    
    public let identifier: UUID
    
    public var isConnected: Bool
    
    // MARK: - Relationships
    
    public let central: String
    
    public var scanData: ScanData
    
    public var services: CentralManager.Service
}
