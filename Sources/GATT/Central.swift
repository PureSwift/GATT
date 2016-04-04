//
//  Central.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/3/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import SwiftFoundation
import Bluetooth

/// GATT Central Manager
///
/// Implementation varies by operating system.
public protocol NativeCentral {
    
    var log: (String -> ())? { get set }
    
    func scan(duration: Int) -> [Peripheral]
    
    func connect(peripheral: Peripheral, timeout: Int) throws
}

/// The default timeout for Central operations.
internal let DefaultCentralTimeout = 5