//
//  AsyncStream.swift
//
//
//  Created by Alsey Coleman Miller on 4/17/22.
//

#if !EMBEDDED_NO_CONCURRENCY

#if hasFeature(Embedded)
// Embedded Swift does not import the concurrency module implicitly.
import _Concurrency
#endif
import Bluetooth

// MARK: - Scan

/// Scan results from a ``CentralManager``, failing with its `Failure`.
///
/// Hosted builds are backed by `AsyncIndefiniteStream`. Embedded builds, which
/// have no `any Error`, use a single-threaded stream with a typed failure and
/// offer only the initializer that takes a continuation.
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public struct AsyncCentralScan <Central: CentralManager>: AsyncSequence, Sendable {

    public typealias Element = ScanData<Central.Peripheral, Central.Advertisement>

    public typealias Failure = Central.Failure

    #if hasFeature(Embedded)
    public typealias Continuation = AsyncCentralContinuation<Element, Failure>

    let stream: AsyncCentralStream<Element, Failure>
    #else
    public typealias Continuation = AsyncIndefiniteStream<Element>.Continuation

    let stream: AsyncIndefiniteStream<Element>
    #endif

    /// A stream fed by a continuation, such as from a delegate callback.
    ///
    /// `onTermination` runs when the stream is stopped, its task is cancelled
    /// or it's released. Embedded builds run it once; hosted builds, backed by
    /// `AsyncIndefiniteStream`, run it again on release after a stop, so it
    /// should be safe to repeat. Finish with an error of type `Failure`.
    public init(
        bufferSize: Int = 100,
        onTermination: @escaping () -> (),
        _ build: (Continuation) -> ()
    ) {
        self.stream = .init(bufferSize: bufferSize, onTermination: onTermination, build)
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(iterator: stream.makeAsyncIterator())
    }

    public func stop() {
        stream.stop()
    }

    public var isScanning: Bool {
        return stream.isExecuting
    }
}

#if !hasFeature(Embedded)
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public extension AsyncCentralScan where Central.Failure == any Error {

    /// A stream fed by an async closure, run in its own task until the stream
    /// is stopped. Only for conformers with untyped errors, since the closure
    /// may throw anything.
    init(
        bufferSize: Int = 100,
        _ build: @escaping @Sendable ((Element) -> ()) async throws -> ()
    ) {
        self.stream = .init(bufferSize: bufferSize, build)
    }
}
#endif

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public extension AsyncCentralScan {

    struct AsyncIterator: AsyncIteratorProtocol {

        #if hasFeature(Embedded)
        var iterator: AsyncCentralStream<Element, Central.Failure>.AsyncIterator
        #else
        var iterator: AsyncIndefiniteStream<Element>.AsyncIterator
        #endif

        public mutating func next() async throws(Central.Failure) -> Element? {
            #if hasFeature(Embedded)
            return try await iterator.next()
            #else
            return try await rethrowing(Central.Failure.self) { try await iterator.next() }
            #endif
        }
    }

    /// The first scan result; stops the scan.
    func first() async throws(Central.Failure) -> Element? {
        // `next()` directly, rather than `for try await`, keeps the error typed
        // on OS versions whose `AsyncSequence` has no `Failure`.
        var iterator = makeAsyncIterator()
        let element = try await iterator.next()
        stop()
        return element
    }
}

// MARK: - Notifications

/// Characteristic notifications from a ``CentralManager``, failing with its
/// `Failure`. Backed like ``AsyncCentralScan``.
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public struct AsyncCentralNotifications <Central: CentralManager>: AsyncSequence, Sendable {

    public typealias Element = Central.Data

    public typealias Failure = Central.Failure

    #if hasFeature(Embedded)
    public typealias Continuation = AsyncCentralContinuation<Element, Failure>

    let stream: AsyncCentralStream<Element, Failure>
    #else
    public typealias Continuation = AsyncIndefiniteStream<Element>.Continuation

    let stream: AsyncIndefiniteStream<Element>
    #endif

    /// A stream fed by a continuation, such as from a delegate callback.
    ///
    /// `onTermination` runs when the stream is stopped, its task is cancelled
    /// or it's released. Embedded builds run it once; hosted builds, backed by
    /// `AsyncIndefiniteStream`, run it again on release after a stop, so it
    /// should be safe to repeat. Finish with an error of type `Failure`.
    public init(
        bufferSize: Int = 100,
        onTermination: @escaping () -> (),
        _ build: (Continuation) -> ()
    ) {
        self.stream = .init(bufferSize: bufferSize, onTermination: onTermination, build)
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(iterator: stream.makeAsyncIterator())
    }

    public func stop() {
        stream.stop()
    }

    public var isNotifying: Bool {
        return stream.isExecuting
    }
}

#if !hasFeature(Embedded)
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public extension AsyncCentralNotifications where Central.Failure == any Error {

    /// A stream fed by an async closure, run in its own task until the stream
    /// is stopped. Only for conformers with untyped errors, since the closure
    /// may throw anything.
    init(
        bufferSize: Int = 100,
        _ build: @escaping @Sendable ((Element) -> ()) async throws -> ()
    ) {
        self.stream = .init(bufferSize: bufferSize, build)
    }
}
#endif

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public extension AsyncCentralNotifications {

    struct AsyncIterator: AsyncIteratorProtocol {

        #if hasFeature(Embedded)
        var iterator: AsyncCentralStream<Element, Central.Failure>.AsyncIterator
        #else
        var iterator: AsyncIndefiniteStream<Element>.AsyncIterator
        #endif

        public mutating func next() async throws(Central.Failure) -> Element? {
            #if hasFeature(Embedded)
            return try await iterator.next()
            #else
            return try await rethrowing(Central.Failure.self) { try await iterator.next() }
            #endif
        }
    }
}

// MARK: - Hosted error typing

#if !hasFeature(Embedded)
/// Runs `body` and rethrows its error as `Failure`.
///
/// `AsyncIndefiniteStream` carries `any Error`. A conformer finishes its stream
/// with its own `Failure` (for untyped conformers, `any Error` itself), so the
/// cast succeeds; anything else is a bug in the conformer.
@inline(__always)
internal func rethrowing<T, Failure: Error>(
    _ failure: Failure.Type,
    _ body: () async throws -> T
) async throws(Failure) -> T {
    do {
        return try await body()
    } catch let error as Failure {
        throw error
    } catch {
        preconditionFailure("A central's stream finished with \(error), which isn't its Failure type \(Failure.self)")
    }
}
#endif

// MARK: - Single-threaded stream

/// The continuation Embedded builds pass to a stream's `build` closure.
///
/// Embedded builds are single-threaded: yield and finish on the thread that
/// iterates the stream.
public struct AsyncCentralContinuation<Element: Sendable, Failure: Error>: Sendable {

    let storage: AsyncCentralStream<Element, Failure>.Storage

    /// Delivers an element, or buffers it until the stream is iterated.
    public func yield(_ value: Element) {
        storage.yield(value)
    }

    /// Ends the stream after any buffered elements.
    public func finish() {
        storage.finish(.success(()))
    }

    /// Ends the stream with `error`, after any buffered elements.
    public func finish(throwing error: Failure) {
        storage.finish(.failure(error))
    }
}

/// A single-threaded stream with a typed failure: what the central streams use
/// in Embedded Swift, where `AsyncThrowingStream` would need `any Error`.
///
/// It behaves like `AsyncIndefiniteStream`: it keeps the newest `bufferSize`
/// elements, delivers what's buffered before it ends, and runs `onTermination`
/// once, when it's stopped, its task is cancelled while waiting, or it's
/// released. It's built on every platform so hosted tests can run it; only
/// Embedded builds use it.
struct AsyncCentralStream<Element: Sendable, Failure: Error>: Sendable {

    let storage: Storage

    init(
        bufferSize: Int = 100,
        onTermination: @escaping () -> (),
        _ build: (AsyncCentralContinuation<Element, Failure>) -> ()
    ) {
        precondition(bufferSize > 0, "bufferSize must be positive")
        let storage = Storage(bufferSize: bufferSize, onTermination: onTermination)
        self.storage = storage
        build(AsyncCentralContinuation(storage: storage))
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(storage: storage)
    }

    func stop() {
        storage.stop()
    }

    var isExecuting: Bool {
        storage.isExecuting
    }

    struct AsyncIterator {

        let storage: Storage

        // Runs on the caller's executor: the stream is single-threaded, so the
        // iterator must stay with the code that yields to it.
        nonisolated(nonsending) func next() async throws(Failure) -> Element? {
            try await storage.next()
        }
    }

    final class Storage: @unchecked Sendable {

        let bufferSize: Int

        var buffer = [Element]()

        /// Set when the producer finishes or the stream stops. An error is
        /// delivered once, after the buffer drains.
        var completion: Result<Void, Failure>?

        /// The iterator waiting for the next element.
        var waiter: UnsafeContinuation<Result<Element?, Failure>, Never>?

        var onTermination: (() -> ())?

        init(bufferSize: Int, onTermination: @escaping () -> ()) {
            self.bufferSize = bufferSize
            self.onTermination = onTermination
        }

        deinit {
            terminate()
        }

        var isExecuting: Bool {
            completion == nil && onTermination != nil
        }

        func yield(_ value: Element) {
            guard completion == nil else { return }
            if let waiter {
                self.waiter = nil
                waiter.resume(returning: .success(value))
            } else {
                buffer.append(value)
                if buffer.count > bufferSize {
                    buffer.removeFirst(buffer.count - bufferSize)
                }
            }
        }

        func finish(_ result: Result<Void, Failure>) {
            guard completion == nil else { return }
            if let waiter {
                // the buffer is empty while an iterator waits
                self.waiter = nil
                completion = .success(())
                waiter.resume(returning: result.map { nil })
            } else {
                completion = result
            }
        }

        func stop() {
            finish(.success(()))
            terminate()
        }

        func terminate() {
            guard let onTermination else { return }
            self.onTermination = nil
            onTermination()
        }

        nonisolated(nonsending) func next() async throws(Failure) -> Element? {
            if buffer.isEmpty == false {
                return buffer.removeFirst()
            }
            if let completion {
                // an error is thrown once; after it, the stream just ends
                self.completion = .success(())
                try completion.get()
                return nil
            }
            let result = await withTaskCancellationHandler {
                await withUnsafeContinuation { (continuation: UnsafeContinuation<Result<Element?, Failure>, Never>) in
                    if self.completion != nil {
                        // cancelled before this iterator began waiting
                        continuation.resume(returning: .success(nil))
                    } else {
                        self.waiter = continuation
                    }
                }
            } onCancel: {
                self.cancel()
            }
            return try result.get()
        }

        private func cancel() {
            if let waiter {
                self.waiter = nil
                completion = .success(())
                waiter.resume(returning: .success(nil))
            }
            stop()
        }
    }
}

#endif
