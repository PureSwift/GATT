//
//  PeripheralContinuation.wift
//  
//
//  Created by Alsey Coleman Miller on 20/12/21.
//

#if canImport(CoreBluetooth)
import Foundation
import Bluetooth
import GATT

#if DEBUG
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
internal struct PeripheralContinuation<T, E> where T: Sendable, E: Error {
    
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
    }
    
    func resume(
        returning value: T
    ) {
        continuation.resume(returning: value)
    }
    
    func resume(
        throwing error: E
    ) {
        continuation.resume(throwing: error)
    }
    
    func resume(
        with result: Result<T, E>
    ) {
        continuation.resume(with: result)
    }
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension PeripheralContinuation where T == Void {
    
    func resume() {
        self.resume(returning: ())
    }
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
internal func withContinuation<T>(
    for peripheral: DarwinCentral.Peripheral,
    function: String = #function,
    _ body: (PeripheralContinuation<T, Never>) -> Void
) async -> T {
    return await withUnsafeContinuation {
        body(PeripheralContinuation(continuation: $0, function: function, peripheral: peripheral))
    }
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
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
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
internal typealias PeripheralContinuation<T, E> = CheckedContinuation<T, E> where E: Error

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
@inline(__always)
internal func withContinuation<T>(
    for peripheral: DarwinCentral.Peripheral,
    function: String = #function,
    _ body: (CheckedContinuation<T, Never>) -> Void
) async -> T {
    return await withCheckedContinuation(function: function, body)
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
@inline(__always)
internal func withThrowingContinuation<T>(
    for peripheral: DarwinCentral.Peripheral,
    function: String = #function,
    _ body: (CheckedContinuation<T, Swift.Error>) -> Void
) async throws -> T {
    return try await withCheckedThrowingContinuation(function: function, body)
}
#endif
#endif
