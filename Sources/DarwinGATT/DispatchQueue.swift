//
//  DispatchQueue.swift
//  SmartConnect
//
//  Created by Alsey Coleman Miller on 7/23/18.
//
//

import Foundation
import Dispatch

internal extension DispatchQueue {
    
    ///
    /// Submits a block for synchronous execution on this queue.
    ///
    /// Submits a work item to a dispatch queue like `sync(execute:)`, and returns
    /// the value, of type `T`, returned by that work item.
    ///
    /// - parameter execute: The work item to be invoked on the queue.
    /// - returns the value returned by the work item.
    /// - SeeAlso: `sync(execute:)`
    ///
    @inline(__always)
    func _sync <T> (execute work: () throws -> T) rethrows -> T {
        
        #if swift(>=3.2)
        return try sync(execute: work)
        #elseif swift(>=3.0)
        return try sync(flags: [], execute: work)
        #endif
    }
}
