//
//  Queue.swift
//  
//
//  Created by Alsey Coleman Miller on 21/12/21.
//

internal struct Queue<Operation> {
    
    private(set) var operations = [Operation]()
    
    private let execute: (Operation) -> Bool
    
    init(_ execute: @escaping (Operation) -> Bool) {
        self.execute = execute
    }
    
    var current: Operation? {
        operations.first
    }
    
    var isEmpty: Bool {
        operations.isEmpty
    }
    
    mutating func push(_ operation: Operation) {
        operations.append(operation)
        // execute immediately if none pending
        if operations.count == 1 {
            executeCurrent()
        }
    }
    
    mutating func pop(_ body: (Operation) -> ()) {
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
    
    mutating func popFirst<T>(
        where filter: (Operation) -> (T?),
        _ body: (Operation, T) -> ()
    ) {
        for (index, queuedOperation) in operations.enumerated() {
            guard let operation = filter(queuedOperation) else {
                continue
            }
            // execute completion
            body(queuedOperation, operation)
            operations.remove(at: index)
            executeCurrent()
            return
        }
        assertionFailure()
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
