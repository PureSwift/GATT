//
//  Array.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 8/1/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation

#if swift(>=3.1)
#elseif swift(>=3.0)
    
    internal extension Array {
        
        static func += (lhs: inout Array, rhs: Array) {
            
            lhs.append(contentsOf: rhs)
        }
    }
    
#endif
