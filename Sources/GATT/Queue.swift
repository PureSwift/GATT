//
//  Queue.swift
//  
//
//  Created by Alsey Coleman Miller on 4/5/22.
//

internal struct Queue<T> {

     private(set) var elements = [T]()

     init() {
         elements.reserveCapacity(2)
     }

     var isEmpty: Bool {
         elements.isEmpty
     }

     mutating func push(_ element: T) {
         elements.append(element)
     }

     mutating func pop() -> T? {
         guard isEmpty == false else {
             return nil
         }
         // finish and remove current
         return elements.removeFirst()
     }
 }
