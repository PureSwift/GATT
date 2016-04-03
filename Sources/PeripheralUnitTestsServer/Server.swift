//
//  Server.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/3/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import Foundation
import XCTest
import Bluetooth
import GATT

final class ServerManager {
    
    // MARK: - Properties
    
    let server = Server()
    
    private(set) var readServices: [Bluetooth.UUID] = []
    
    private(set) var didWait = false
}