//
//  Characteristic+.swift
//  BluetoothExplorer
//
//  Created by Carlos Duclos on 5/13/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import GATT
import Bluetooth

extension CentralManager.Characteristic {
    
    var formattedProperties: String { return properties.reduce("") { $0 + $1.name + " " } }
    
}
