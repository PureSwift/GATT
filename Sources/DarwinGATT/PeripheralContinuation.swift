//
//  PeripheralContinuation.wift
//  
//
//  Created by Alsey Coleman Miller on 20/12/21.
//

import Foundation
import Bluetooth
import GATT

internal final class PeripheralContinuation<T, E> where E: Error {
    
    typealias Peripheral = DarwinCentral.Peripheral
    
    private let function: String
    
    private let continuation: CheckedContinuation<T, E>
    
    private let peripheral: DarwinCentral.Peripheral
    
    private let log: ((String) -> ())?
    
    fileprivate init(
        continuation: UnsafeContinuation<T, E>,
        function: String,
        peripheral: Peripheral,
        log: ((String) -> ())? = nil
    ) {
        self.continuation = CheckedContinuation(continuation: continuation, function: function)
        self.function = function
        self.peripheral = peripheral
        self.log = log
    }
    
    func resume(
        returning value: T,
        function: String = #function
    ) {
        #if DEBUG
        print("Will resume continuation \(self.function) for peripheral \(peripheral), returning \(value) in \(function)")
        #endif
        continuation.resume(returning: value)
    }
    
    func resume(
        throwing error: E,
        function: String = #function
    ) {
        #if DEBUG
        print("Will resume continuation \(self.function) for peripheral \(peripheral), throwing \(error) in \(function)")
        #endif
        continuation.resume(throwing: error)
    }
}

extension PeripheralContinuation where T == Void {
    
    func resume() {
      self.resume(returning: ())
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
