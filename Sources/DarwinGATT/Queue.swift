//
//  Queue.swift
//  
//
//  Created by Alsey Coleman Miller on 21/12/21.
//

internal struct Queue<T> {
    
    private(set) var operations = [T]()
    
    private let execute: (T) -> Bool
    
    init(_ execute: @escaping (T) -> Bool) {
        self.execute = execute
    }
    
    var current: T? {
        operations.first
    }
    
    mutating func push(_ operation: T) {
        operations.append(operation)
        // execute immediately if none pending
        if operations.count == 1 {
            executeCurrent()
        }
    }
    
    mutating func pop(_ body: (T) -> ()) {
        guard let operation = self.current else {
            assertionFailure("No pending tasks")
            return
        }
        // finish and remove current
        body(operation)
        operations.removeFirst()
        // execute next
        executeCurrent()
    }
    
    private mutating func executeCurrent() {
        if let operation = self.current {
            guard execute(operation) else {
                operations.removeFirst()
                executeCurrent() // execute next
                return
            }
            // wait for continuation
        }
    }
}
