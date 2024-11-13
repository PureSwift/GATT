//
//  AsyncStream.swift
//  
//
//  Created by Alsey Coleman Miller on 4/17/22.
//

#if !hasFeature(Embedded)
import Bluetooth
import AsyncAlgorithms

public struct AsyncCentralScan <Central: CentralManager>: AsyncSequence {

    public typealias Element = ScanData<Central.Peripheral, Central.Advertisement>
    
    public typealias Channel = AsyncThrowingChannel<Element, Swift.Error>
    
    let channel: Channel
    
    public init() {
        self.channel = .init()
    }
    
    public func append(_ element: Element) async {
        await channel.send(element)
    }
    
    public func makeAsyncIterator() -> Channel.AsyncIterator {
        channel.makeAsyncIterator()
    }
    
    public func stop() {
        channel.finish()
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

    public typealias Element = Central.Data
    
    public typealias Channel = AsyncThrowingChannel<Element, Swift.Error>
    
    let channel: Channel
    
    public init() {
        self.channel = .init()
    }
    
    public func append(_ element: Element) async {
        await channel.send(element)
    }
    
    public func makeAsyncIterator() -> Channel.AsyncIterator {
        channel.makeAsyncIterator()
    }
    
    public func stop() {
        channel.finish()
    }
}

#endif
