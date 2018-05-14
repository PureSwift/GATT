//
//  CharacteristicProperty.swift
//  BluetoothExplorer
//
//  Created by Carlos Duclos on 5/13/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import GATT
import Bluetooth

extension GATT.CharacteristicProperty {
    
    var name: String {
        switch self {
        case .broadcast: return "broadcast"
        case .read: return "read"
        case .writeWithoutResponse: return "write nr"
        case .write: return "write"
        case .notify: return "notify"
        case .indicate: return "indicate"
        case .signedWrite: return "signed write"
        case .extendedProperties: return "extended"
        }
    }
}
