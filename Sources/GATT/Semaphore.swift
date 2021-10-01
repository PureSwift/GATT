//
//  Semaphore.swift
//  
//
//  Created by Alsey Coleman Miller on 6/10/20.
//

#if canImport(Dispatch)
import Foundation
import Dispatch

internal final class Semaphore <Success> {
    
    let timeout: TimeInterval
    private let semaphore: DispatchSemaphore
    private(set) var result: Result<Success, Error>?
    
    init(timeout: TimeInterval) {
        self.timeout = timeout
        self.semaphore = DispatchSemaphore(value: 0)
    }
    
    func wait() throws -> Success {
        precondition(result == nil)
        let dispatchTime: DispatchTime = .now() + timeout
        let success = semaphore.wait(timeout: dispatchTime) == .success
        guard let result = self.result, success
            else { throw CentralError.timeout }
        switch result {
        case let .failure(error):
            throw error
        case let .success(value):
            return value
        }
    }
    
    func stopWaiting(_ result: Result<Success, Error>) {
        precondition(self.result == nil)
        self.result = result
        semaphore.signal()
    }
}
#endif
