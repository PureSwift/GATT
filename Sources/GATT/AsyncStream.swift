//
//  AsyncStream.swift
//  
//
//  Created by Alsey Coleman Miller on 4/17/22.
//

import Foundation
import Bluetooth

public final class AsyncCentralScan <Central: CentralManager>: AsyncSequence {

    public typealias Element = ScanData<Central.Peripheral, Central.Advertisement>
    
    let stream: AsyncIndefiniteStream<Element>
    
    deinit {
        if stream.didStop == false {
            stream.stop()
        }
    }
    
    public init(
        bufferSize: Int = 100,
        unfolding produce: @escaping () async throws -> Element
    ) {
        self.stream = .init(bufferSize: bufferSize, unfolding: produce)
    }
    
    public init(
        bufferSize: Int = 100,
        _ build: @escaping (AsyncIndefiniteStream<Element>.Continuation) async throws -> ()
    ) {
        self.stream = .init(bufferSize: bufferSize, build)
    }
    
    public func makeAsyncIterator() -> AsyncIndefiniteStream<Element>.AsyncIterator {
        stream.makeAsyncIterator()
    }
    
    public func stop() {
        stream.stop()
    }
    
    public var isScanning: Bool {
        return stream.didStop == false
    }
}

public final class AsyncCentralNotifications <Central: CentralManager>: AsyncSequence {

    public typealias Element = Data
    
    let stream: AsyncIndefiniteStream<Element>
    
    public init(
        bufferSize: Int = 100,
        unfolding produce: @escaping () async throws -> Element
    ) {
        self.stream = .init(bufferSize: bufferSize, unfolding: produce)
    }
    
    public init(
        bufferSize: Int = 100,
        _ build: @escaping (AsyncIndefiniteStream<Element>.Continuation) async throws -> ()
    ) {
        self.stream = .init(bufferSize: bufferSize, build)
    }
    
    public func makeAsyncIterator() -> AsyncIndefiniteStream<Element>.AsyncIterator {
        stream.makeAsyncIterator()
    }
    
    public func stop() {
        stream.stop()
    }
    
    public var isNotifying: Bool {
        return stream.didStop == false
    }
}
