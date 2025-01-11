//
//  AsyncStream.swift
//  
//
//  Created by Alsey Coleman Miller on 4/17/22.
//

#if !hasFeature(Embedded)
import Foundation
import Bluetooth

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public struct AsyncCentralScan <Central: CentralManager>: AsyncSequence, Sendable {

    public typealias Element = ScanData<Central.Peripheral, Central.Advertisement>
    
    let stream: AsyncIndefiniteStream<Element>
    
    public init(
        bufferSize: Int = 100,
        _ build: @escaping @Sendable ((Element) -> ()) async throws -> ()
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

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public extension AsyncCentralScan {
    
    func first() async throws -> Element? {
        for try await element in self {
            self.stop()
            return element
        }
        return nil
    }
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public struct AsyncCentralNotifications <Central: CentralManager>: AsyncSequence, Sendable {

    public typealias Element = Central.Data
    
    let stream: AsyncIndefiniteStream<Element>
    
    public init(
        bufferSize: Int = 100,
        _ build: @escaping @Sendable ((Element) -> ()) async throws -> ()
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
#endif
