//
//  CharacteristicViewController.swift
//  BluetoothExplorer
//
//  Created by Alsey Coleman Miller on 6/20/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import UIKit
import Bluetooth

protocol CharacteristicViewController: class {
    
    /// The GATT Characteristic type this view controller can edit.
    associatedtype CharacteristicValue: GATTCharacteristic
    
    /// Initialize and load from characteristic data.
    static func load(data: Data) -> Self
    
    var view: UIView! { get }
    
    /// The current value.
    var value: CharacteristicValue { get }
    
    /// Value changed closure. 
    var valueDidChange: ((CharacteristicValue) -> ())? { get set }
}

extension CharacteristicViewController {
    
    /// The UUID of the Bluetooth Characteristic this view controller can edit.
    static var uuid: BluetoothUUID {
        
        return CharacteristicValue.uuid
    }
}


