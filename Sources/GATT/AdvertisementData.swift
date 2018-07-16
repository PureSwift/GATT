//
//  AdvertisementData.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 3/9/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import Bluetooth

/// GATT Advertisement Data.
public protocol AdvertisementData: Equatable {
    
    var localName: String? { get }
    
    var manufacturerData: Data? { get }
    
    var isConnectable: Bool? { get }
}
