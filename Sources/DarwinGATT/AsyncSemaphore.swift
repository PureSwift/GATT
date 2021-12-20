//
//  AsyncSemaphore.swift
//  
//
//  Created by Alsey Coleman Miller on 19/12/21.
//

import Foundation

/// An object that controls access to a resource across multiple execution contexts through use of a traditional counting semaphore.
///
/// You increment a semaphore count by calling the signal() method, and decrement a semaphore count by calling `wait()`.
internal final class AsyncSemaphore {
    
    private var value: Int
    
    private let lock = NSLock()
    
    private var waitingContinuations = [CheckedContinuation<Void, Never>]()
    
    public init(value: Int = 0) {
        self.value = value
    }
    
    /// Waits for (decrements) a semaphone.
    ///
    /// Decrement the counting semaphore.
    /// If the resulting value is less than zero, this function waits for a signal to occur before returning.
    public func wait() async {
        // decrements
        lock.lock()
        value -= 1
        // wait if neccesary
        if value < 0 {
            await withCheckedContinuation() { (continuation: CheckedContinuation<Void, Never>) in
                waitingContinuations.append(continuation)
                lock.unlock()
            }
        } else {
            lock.unlock()
        }
    }
    
    /// Signals (increments) a semaphore.
    ///
    /// Increment the counting semaphore.
    /// If the previous value was less than zero, this function wakes a thread currently waiting
    @discardableResult
    public func signal() -> Int {
        lock.lock()
        // increment
        let oldValue = value
        let newValue = oldValue + 1
        value = newValue
        // resume continuations
        if oldValue < 0, newValue >= 0 {
            waitingContinuations.forEach { $0.resume() }
            waitingContinuations.removeAll(keepingCapacity: true)
        }
        lock.unlock()
        return newValue
    }
}
