//
//  PeripheralContinuation.wift
//  
//
//  Created by Alsey Coleman Miller on 20/12/21.
//

import Foundation
import Bluetooth
import GATT

#if os(macOS)
internal struct PeripheralContinuation<T, E> where E: Error {
    
    static var log: (String) -> () = {
        #if DEBUG
        print($0)
        #endif
    }
    
    private let function: String
    
    private let continuation: CheckedContinuation<T, E>
    
    private let peripheral: DarwinCentral.Peripheral
    
    fileprivate init(
        continuation: UnsafeContinuation<T, E>,
        function: String,
        peripheral: DarwinCentral.Peripheral
    ) {
        self.continuation = CheckedContinuation(continuation: continuation, function: function)
        self.function = function
        self.peripheral = peripheral
        Self.log("Will wait for continuation '\(self.function)'")
    }
    
    func resume(
        returning value: T,
        function: String = #function
    ) {
        Self.log("Will resume continuation '\(self.function)' for peripheral \(peripheral), returning in '\(function)'")
        continuation.resume(returning: value)
    }
    
    func resume(
        throwing error: E,
        function: String = #function
    ) {
        Self.log("Will resume continuation '\(self.function)' for peripheral \(peripheral), throwing in '\(function)' (\(error.localizedDescription))")
        continuation.resume(throwing: error)
    }
}

extension PeripheralContinuation where T == Void {
    
    func resume(function: String = #function) {
        self.resume(returning: (), function: function)
    }
}

internal func withContinuation<T>(
    for peripheral: DarwinCentral.Peripheral,
    function: String = #function,
    _ body: (PeripheralContinuation<T, Never>) -> Void
) async -> T {
    return await withUnsafeContinuation {
        body(PeripheralContinuation(continuation: $0, function: function, peripheral: peripheral))
    }
}

internal func withThrowingContinuation<T>(
    for peripheral: DarwinCentral.Peripheral,
    function: String = #function,
    _ body: (PeripheralContinuation<T, Swift.Error>) -> Void
) async throws -> T {
    return try await withUnsafeThrowingContinuation {
        body(PeripheralContinuation(continuation: $0, function: function, peripheral: peripheral))
    }
}
#else
internal typealias PeripheralContinuation<T, E> = CheckedContinuation<T, E> where E: Error

@inline(__always)
internal func withContinuation<T>(
    for peripheral: DarwinCentral.Peripheral,
    function: String = #function,
    _ body: (CheckedContinuation<T, Never>) -> Void
) async -> T {
    return await withCheckedContinuation(function: function, body)
}

@inline(__always)
internal func withThrowingContinuation<T>(
    for peripheral: DarwinCentral.Peripheral,
    function: String = #function,
    _ body: (CheckedContinuation<T, Swift.Error>) -> Void
) async throws -> T {
    return try await withCheckedThrowingContinuation(function: function, body)
}
#endif
