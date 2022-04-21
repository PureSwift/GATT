//
//  AsyncStream.swift
//  
//
//  Created by Alsey Coleman Miller on 4/17/22.
//

import Foundation
import Bluetooth

public struct AsyncCentralScan <Central: CentralManager>: AsyncSequence {

    public typealias Element = ScanData<Central.Peripheral, Central.Advertisement>
    
    let stream: AsyncIndefiniteStream<Element>
    
    public init(
        bufferSize: Int = 100,
        _ build: @escaping ((Element) -> ()) async throws -> ()
    ) {
        self.stream = .init(bufferSize: bufferSize, build)
    }
    
    public init(
        bufferSize: Int = 100,
        onTermination: @escaping () -> (),
        _ build: (AsyncIndefiniteStream<Element>.Continuation) -> ()
    ) {
        self.stream = .init(bufferSize: bufferSize, onTermination: onTermination, build)
    }
    
    public func makeAsyncIterator() -> AsyncIndefiniteStream<Element>.AsyncIterator {
        stream.makeAsyncIterator()
    }
    
    public func stop() {
        stream.stop()
    }
    
    public var isScanning: Bool {
        return stream.isExecuting
    }
}

public extension AsyncCentralScan {
    
    func first() async throws -> Element? {
        for try await element in self {
            self.stop()
            return element
        }
        return nil
    }
}

public struct AsyncCentralNotifications <Central: CentralManager>: AsyncSequence {

    public typealias Element = Data
    
    let stream: AsyncIndefiniteStream<Element>
    
    public init(
        bufferSize: Int = 100,
        _ build: @escaping ((Element) -> ()) async throws -> ()
    ) {
        self.stream = .init(bufferSize: bufferSize, build)
    }
    
    public init(
        bufferSize: Int = 100,
        onTermination: @escaping () -> (),
        _ build: (AsyncIndefiniteStream<Element>.Continuation) -> ()
    ) {
        self.stream = .init(bufferSize: bufferSize, onTermination: onTermination, build)
    }
    
    public func makeAsyncIterator() -> AsyncIndefiniteStream<Element>.AsyncIterator {
        stream.makeAsyncIterator()
    }
    
    public func stop() {
        stream.stop()
    }
    
    public var isNotifying: Bool {
        return stream.isExecuting
    }
}
