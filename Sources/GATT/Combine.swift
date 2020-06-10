//
//  Combine.swift
//  
//
//  Created by Alsey Coleman Miller on 6/9/20.
//

#if canImport(Foundation)
import Foundation
#elseif canImport(SwiftFoundation)
import SwiftFoundation
#endif

#if canImport(Combine)
import Combine
#elseif canImport(OpenCombine)
import OpenCombine
#endif

import Bluetooth

#if canImport(Combine) || canImport(OpenCombine)

/// GATT Central manager with Combine support.
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
open class CombineCentral <Central: AsynchronousCentral> {
    
    public typealias Peripheral = Central.Peripheral
    
    public typealias Advertisement = Central.Advertisement
        
    public typealias AttributeID = Central.AttributeID
    
    public let central: Central
    
    public var userInfo = [String: Any]()
    
    public init(central: Central) {
        self.central = central
        self.isScanning = central.isScanning
        central.log = { [weak self] in self?.log.send($0) }
        central.scanningChanged = { [weak self] in self?.isScanning = $0 }
        central.didDisconnect = { [weak self] in self?.didDisconnect.send($0) }
    }
    
    /// TODO: Improve logging API, use Logger?
    public let log = PassthroughSubject<String, Error>()
    
    @Published
    public private(set) var isScanning = false
    
    /// Scans for peripherals that are advertising services.
    public func scan(filterDuplicates: Bool) -> ScanPublisher {
        return ScanPublisher(central: central, filterDuplicates: filterDuplicates)
    }
    
    /// Stops scanning for peripherals.
    public func stopScan() {
        central.stopScan()
    }
    
    /// Connect to the specifed peripheral.
    public func connect(to peripheral: Peripheral, timeout: TimeInterval = .gattDefaultTimeout) -> ConnectPublisher {
        return ConnectPublisher(
            central: central,
            peripheral: peripheral,
            timeout: timeout
        )
    }
    
    /// Disconnect from the speciffied peripheral.
    public func disconnect(_ peripheral: Peripheral) {
        central.disconnect(peripheral)
    }
    
    /// Disconnect from all connected peripherals.
    public func disconnectAll() {
        central.disconnectAll()
    }
    
    /// Notifies that a peripheral has been disconnected.
    public let didDisconnect = PassthroughSubject<Peripheral, Error>() // TODO: Make custom publisher
    
    /// Discover the specified services.
    public func discoverServices(_ services: [BluetoothUUID] = [],
                                 for peripheral: Peripheral,
                                 timeout: TimeInterval = .gattDefaultTimeout) -> DiscoverServicesPublisher {
        
        return DiscoverServicesPublisher(
            central: central,
            peripheral: peripheral,
            timeout: timeout,
            services: services
        )
    }
    
    /// Discover characteristics for the specified service.
    public func discoverCharacteristics(_ characteristics: [BluetoothUUID] = [],
                                        for service: Service<Peripheral, AttributeID>,
                                        timeout: TimeInterval = .gattDefaultTimeout) -> DiscoverCharacteristicsPublisher {
        
        return DiscoverCharacteristicsPublisher(
            central: central,
            timeout: timeout,
            characteristics: characteristics,
            service: service
        )
    }
    
    /// Read characteristic value.
    public func readValue(for characteristic: Characteristic<Peripheral, AttributeID>,
                          timeout: TimeInterval = .gattDefaultTimeout) -> ReadCharacteristicValuePublisher {
        
        return ReadCharacteristicValuePublisher(
            central: central,
            timeout: timeout,
            characteristic: characteristic
        )
    }
    
    /// Write characteristic value.
    public func writeValue(_ data: Data,
                           for characteristic: Characteristic<Peripheral, AttributeID>,
                           withResponse: Bool,
                           timeout: TimeInterval = .gattDefaultTimeout) -> WriteCharacteristicValuePublisher {
        
        return WriteCharacteristicValuePublisher(
            central: central,
            timeout: timeout,
            characteristic: characteristic,
            value: data,
            withResponse: withResponse
        )
    }
    
    /// Subscribe to notifications for the specified characteristic.
    public func notify(for characteristic: Characteristic<Peripheral, AttributeID>,
                       timeout: TimeInterval = .gattDefaultTimeout) -> NotificationPublisher {
        
        return NotificationPublisher(
            central: central,
            timeout: timeout,
            characteristic: characteristic
        )
    }
    
    /// Get the maximum transmission unit for the specified peripheral.
    public func maximumTransmissionUnit(for peripheral: Peripheral) -> Future<ATTMaximumTransmissionUnit, Error> {
        
        return Future { [weak self] in
            self?.central.maximumTransmissionUnit(for: peripheral, completion: $0)
        }
    }
}

// MARK: - Supporting Types

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public extension CombineCentral {
    
    /// GATT Scan Publisher
    struct ScanPublisher: Publisher {
        
        public typealias Output = ScanData<Peripheral, Advertisement>
        
        public typealias Failure = Error
        
        public let central: Central
        
        public let filterDuplicates: Bool
        
        /// This function is called to attach the specified `Subscriber` to this `Publisher` by `subscribe(_:)`
        ///
        /// - SeeAlso: `subscribe(_:)`
        /// - Parameters:
        ///     - subscriber: The subscriber to attach to this `Publisher`.
        ///                   once attached it can begin to receive values.
        public func receive<S>(subscriber: S) where S : Subscriber, Self.Failure == S.Failure, Self.Output == S.Input {
            
            let subscription = ScanSubscription(
                parent: self,
                downstream: subscriber
            )
            subscriber.receive(subscription: subscription)
        }
        
        private final class ScanSubscription <Downstream: Subscriber>: Subscription, CustomStringConvertible where Downstream.Input == Output, Downstream.Failure == Failure {
            
            private var parent: ScanPublisher?
            
            private var downstream: Downstream?
            
            private var demand = Subscribers.Demand.none
            
            fileprivate init(parent: ScanPublisher,
                             downstream: Downstream) {
                
                self.parent = parent
                self.downstream = downstream
                
                // start scanning
                parent.central.scan(filterDuplicates: parent.filterDuplicates) { [weak self] in
                    self?.didRecieve($0, downstream: downstream)
                }
            }
            
            var description: String { return "ScanPublisher" }
            
            private func didRecieve(_ result: Result<Output, Failure>, downstream: Downstream) {
                
                guard demand > 0 else {
                    return
                }
                switch result {
                case let .success(value):
                    demand -= 1
                    let newDemand = downstream.receive(value)
                    demand += newDemand
                case let .failure(error):
                    downstream.receive(completion: .failure(error))
                }
            }
            
            func request(_ demand: Subscribers.Demand) {
                self.demand += demand
            }
            
            func cancel() {
                
                guard let central = self.parent?.central
                    else { return }
                central.stopScan()
                self.parent = nil
            }
        }
    }
    
    /// GATT Connect Publisher
    struct ConnectPublisher: Publisher {
        
        public typealias Output = Void
        
        public typealias Failure = Error
        
        public let central: Central
                
        public let peripheral: Central.Peripheral
        
        public let timeout: TimeInterval
        
        /// This function is called to attach the specified `Subscriber` to this `Publisher` by `subscribe(_:)`
        ///
        /// - SeeAlso: `subscribe(_:)`
        /// - Parameters:
        ///     - subscriber: The subscriber to attach to this `Publisher`.
        ///                   once attached it can begin to receive values.
        public func receive<S>(subscriber: S) where S : Subscriber, Self.Failure == S.Failure, Self.Output == S.Input {
            
            let subscription = ConnectSubscription(
                parent: self,
                downstream: subscriber
            )
            subscriber.receive(subscription: subscription)
        }
        
        private final class ConnectSubscription <Downstream: Subscriber>: Subscription, CustomStringConvertible where Downstream.Input == Output, Downstream.Failure == Failure {
            
            private var parent: ConnectPublisher?
            
            private var downstream: Downstream?
            
            private var demand = Subscribers.Demand.none
            
            fileprivate init(parent: ConnectPublisher,
                             downstream: Downstream) {
                
                self.parent = parent
                self.downstream = downstream
            }
            
            var description: String { return "ConnectPublisher" }
            
            func request(_ demand: Subscribers.Demand) {
                
                demand.assertNonZero()
                guard let parent = self.parent else {
                    return
                }
                self.demand += demand
                parent.central.connect(to: parent.peripheral, timeout: parent.timeout) { [weak self] in
                    self?.didComplete($0)
                }
            }
            
            func cancel() {
                guard let parent = self.parent else {
                    return
                }
                parent.central.disconnect(parent.peripheral)
                terminate()
            }
            
            private func didComplete(_ result: Result<Void, Error>) {
                guard demand > 0,
                    let _ = self.parent,
                    let downstream = self.downstream else {
                    return
                }
                terminate()
                switch result {
                case .success:
                    downstream.receive(completion: .finished)
                case let .failure(error):
                    downstream.receive(completion: .failure(error))
                }
            }
            
            private func terminate() {
                parent = nil
                downstream = nil
                demand = .none
            }
        }
    }
    
    /// GATT Discover Services Publisher
    struct DiscoverServicesPublisher: Publisher {
        
        public typealias Output = Service<Peripheral, AttributeID>
        
        public typealias Failure = Error
        
        public let central: Central
                
        public let peripheral: Central.Peripheral
        
        public let timeout: TimeInterval
        
        public let services: [BluetoothUUID]
        
        /// This function is called to attach the specified `Subscriber` to this `Publisher` by `subscribe(_:)`
        ///
        /// - SeeAlso: `subscribe(_:)`
        /// - Parameters:
        ///     - subscriber: The subscriber to attach to this `Publisher`.
        ///                   once attached it can begin to receive values.
        public func receive<S>(subscriber: S) where S : Subscriber, Self.Failure == S.Failure, Self.Output == S.Input {
            
            let subscription = DiscoverServicesSubscription(
                parent: self,
                downstream: subscriber
            )
            subscriber.receive(subscription: subscription)
        }
        
        private final class DiscoverServicesSubscription <Downstream: Subscriber>: Subscription, CustomStringConvertible where Downstream.Input == Output, Downstream.Failure == Failure {
            
            private var parent: DiscoverServicesPublisher?
            
            private var downstream: Downstream?
            
            private var demand = Subscribers.Demand.none
            
            fileprivate init(parent: DiscoverServicesPublisher,
                             downstream: Downstream) {
                
                self.parent = parent
                self.downstream = downstream
            }
            
            var description: String { return "DiscoverServicesPublisher" }
            
            func request(_ demand: Subscribers.Demand) {
                
                demand.assertNonZero()
                guard let parent = self.parent else {
                    return
                }
                self.demand += demand
                parent.central.discoverServices(parent.services, for: parent.peripheral, timeout: parent.timeout) { [weak self] in
                    self?.didComplete($0)
                }
            }
            
            func cancel() {
                guard let _ = self.parent else {
                    return
                }
                terminate()
            }
            
            private func didComplete(_ result: Result<[Output], Error>) {
                guard demand > 0,
                    let _ = self.parent,
                    let downstream = self.downstream else {
                    return
                }
                terminate()
                switch result {
                case let .success(value):
                    value.forEach { _ = downstream.receive($0) }
                    downstream.receive(completion: .finished)
                case let .failure(error):
                    downstream.receive(completion: .failure(error))
                }
            }
            
            private func terminate() {
                parent = nil
                downstream = nil
                demand = .none
            }
        }
    }
    
    /// GATT Discover Characteristics Publisher
    struct DiscoverCharacteristicsPublisher: Publisher {
        
        public typealias Output = Characteristic<Peripheral, AttributeID>
        
        public typealias Failure = Error
        
        public let central: Central
        
        public let timeout: TimeInterval
        
        public let characteristics: [BluetoothUUID]
        
        public let service: Service<Peripheral, AttributeID>
        
        /// This function is called to attach the specified `Subscriber` to this `Publisher` by `subscribe(_:)`
        ///
        /// - SeeAlso: `subscribe(_:)`
        /// - Parameters:
        ///     - subscriber: The subscriber to attach to this `Publisher`.
        ///                   once attached it can begin to receive values.
        public func receive<S>(subscriber: S) where S : Subscriber, Self.Failure == S.Failure, Self.Output == S.Input {
            
            let subscription = DiscoverCharacteristicsSubscription(
                parent: self,
                downstream: subscriber
            )
            subscriber.receive(subscription: subscription)
        }
        
        private final class DiscoverCharacteristicsSubscription <Downstream: Subscriber>: Subscription, CustomStringConvertible where Downstream.Input == Output, Downstream.Failure == Failure {
            
            private var parent: DiscoverCharacteristicsPublisher?
            
            private var downstream: Downstream?
            
            private var demand = Subscribers.Demand.none
            
            fileprivate init(parent: DiscoverCharacteristicsPublisher,
                             downstream: Downstream) {
                
                self.parent = parent
                self.downstream = downstream
            }
            
            var description: String { return "DiscoverCharacteristicsPublisher" }
            
            func request(_ demand: Subscribers.Demand) {
                
                demand.assertNonZero()
                guard let parent = self.parent else {
                    return
                }
                self.demand += demand
                parent.central.discoverCharacteristics(parent.characteristics, for: parent.service, timeout: parent.timeout) { [weak self] in
                    self?.didComplete($0)
                }
            }
            
            func cancel() {
                guard let _ = self.parent else {
                    return
                }
                terminate()
            }
            
            private func didComplete(_ result: Result<[Output], Error>) {
                guard demand > 0,
                    let _ = self.parent,
                    let downstream = self.downstream else {
                    return
                }
                terminate()
                switch result {
                case let .success(value):
                    value.forEach { _ = downstream.receive($0) }
                    downstream.receive(completion: .finished)
                case let .failure(error):
                    downstream.receive(completion: .failure(error))
                }
            }
            
            private func terminate() {
                parent = nil
                downstream = nil
                demand = .none
            }
        }
    }
    
    /// GATT Read Characteristic Value Publisher
    struct ReadCharacteristicValuePublisher: Publisher {
        
        public typealias Output = Data
        
        public typealias Failure = Error
        
        public let central: Central
        
        public let timeout: TimeInterval
        
        public let characteristic: Characteristic<Peripheral, AttributeID>
        
        /// This function is called to attach the specified `Subscriber` to this `Publisher` by `subscribe(_:)`
        ///
        /// - SeeAlso: `subscribe(_:)`
        /// - Parameters:
        ///     - subscriber: The subscriber to attach to this `Publisher`.
        ///                   once attached it can begin to receive values.
        public func receive<S>(subscriber: S) where S : Subscriber, Self.Failure == S.Failure, Self.Output == S.Input {
            
            let subscription = ReadCharacteristicValueSubscription(
                parent: self,
                downstream: subscriber
            )
            subscriber.receive(subscription: subscription)
        }
        
        private final class ReadCharacteristicValueSubscription <Downstream: Subscriber>: Subscription, CustomStringConvertible where Downstream.Input == Output, Downstream.Failure == Failure {
            
            private var parent: ReadCharacteristicValuePublisher?
            
            private var downstream: Downstream?
            
            private var demand = Subscribers.Demand.none
            
            fileprivate init(parent: ReadCharacteristicValuePublisher,
                             downstream: Downstream) {
                
                self.parent = parent
                self.downstream = downstream
            }
            
            var description: String { return "ReadCharacteristicValuePublisher" }
            
            func request(_ demand: Subscribers.Demand) {
                
                demand.assertNonZero()
                guard let parent = self.parent else {
                    return
                }
                self.demand += demand
                parent.central.readValue(for: parent.characteristic, timeout: parent.timeout) { [weak self] in
                    self?.didComplete($0)
                }
            }
            
            func cancel() {
                guard let _ = self.parent else {
                    return
                }
                terminate()
            }
            
            private func didComplete(_ result: Result<Output, Error>) {
                guard demand > 0,
                    let _ = self.parent,
                    let downstream = self.downstream else {
                    return
                }
                terminate()
                switch result {
                case let .success(value):
                    _ = downstream.receive(value)
                    downstream.receive(completion: .finished)
                case let .failure(error):
                    downstream.receive(completion: .failure(error))
                }
            }
            
            private func terminate() {
                parent = nil
                downstream = nil
                demand = .none
            }
        }
    }
    
    /// GATT Write Characteristic Value Publisher
    struct WriteCharacteristicValuePublisher: Publisher {
        
        public typealias Output = Void
        
        public typealias Failure = Error
        
        public let central: Central
        
        public let timeout: TimeInterval
        
        public let characteristic: Characteristic<Peripheral, AttributeID>
        
        public let value: Data
        
        public let withResponse: Bool
        
        /// This function is called to attach the specified `Subscriber` to this `Publisher` by `subscribe(_:)`
        ///
        /// - SeeAlso: `subscribe(_:)`
        /// - Parameters:
        ///     - subscriber: The subscriber to attach to this `Publisher`.
        ///                   once attached it can begin to receive values.
        public func receive<S>(subscriber: S) where S : Subscriber, Self.Failure == S.Failure, Self.Output == S.Input {
            
            let subscription = WriteCharacteristicValueSubscription(
                parent: self,
                downstream: subscriber
            )
            subscriber.receive(subscription: subscription)
        }
        
        private final class WriteCharacteristicValueSubscription <Downstream: Subscriber>: Subscription, CustomStringConvertible where Downstream.Input == Output, Downstream.Failure == Failure {
            
            private var parent: WriteCharacteristicValuePublisher?
            
            private var downstream: Downstream?
            
            private var demand = Subscribers.Demand.none
            
            fileprivate init(parent: WriteCharacteristicValuePublisher,
                             downstream: Downstream) {
                
                self.parent = parent
                self.downstream = downstream
            }
            
            var description: String { return "WriteCharacteristicValuePublisher" }
            
            func request(_ demand: Subscribers.Demand) {
                
                demand.assertNonZero()
                guard let parent = self.parent else {
                    return
                }
                self.demand += demand
                parent.central.writeValue(parent.value, for: parent.characteristic, withResponse: parent.withResponse, timeout: parent.timeout) { [weak self] in
                    self?.didComplete($0)
                }
            }
            
            func cancel() {
                guard let _ = self.parent else {
                    return
                }
                terminate()
            }
            
            private func didComplete(_ result: Result<Output, Error>) {
                guard demand > 0,
                    let _ = self.parent,
                    let downstream = self.downstream else {
                    return
                }
                terminate()
                switch result {
                case .success:
                    downstream.receive(completion: .finished)
                case let .failure(error):
                    downstream.receive(completion: .failure(error))
                }
            }
            
            private func terminate() {
                parent = nil
                downstream = nil
                demand = .none
            }
        }
    }
    
    /// GATT Notification Publisher
    struct NotificationPublisher: Publisher {
        
        public typealias Output = Data
        
        public typealias Failure = Error
        
        public let central: Central
        
        public let timeout: TimeInterval
        
        public let characteristic: Characteristic<Peripheral, AttributeID>
        
        /// This function is called to attach the specified `Subscriber` to this `Publisher` by `subscribe(_:)`
        ///
        /// - SeeAlso: `subscribe(_:)`
        /// - Parameters:
        ///     - subscriber: The subscriber to attach to this `Publisher`.
        ///                   once attached it can begin to receive values.
        public func receive<S>(subscriber: S) where S : Subscriber, Self.Failure == S.Failure, Self.Output == S.Input {
            
            let subscription = NotificationSubscription(
                parent: self,
                downstream: subscriber
            )
            subscriber.receive(subscription: subscription)
        }
        
        private final class NotificationSubscription <Downstream: Subscriber>: Subscription, CustomStringConvertible where Downstream.Input == Output, Downstream.Failure == Failure {
            
            private var parent: NotificationPublisher?
            
            private var downstream: Downstream?
            
            private var demand = Subscribers.Demand.none
            
            fileprivate init(parent: NotificationPublisher,
                             downstream: Downstream) {
                
                self.parent = parent
                self.downstream = downstream
                
                // start observing notifications
                parent.central.notify({ [weak self] in
                    self?.didRecieve($0)
                    }, for: parent.characteristic, timeout: parent.timeout, completion: { [weak self] in
                        self?.registered($0)
                })
            }
            
            var description: String { return "NotificationPublisher" }
            
            private func registered(_ result: Result<Void, Error>) {
                
                guard demand > 0,
                    let _ = self.parent,
                    let downstream = self.downstream else {
                    return
                }
                switch result {
                case .success:
                    break // do nothing
                case let .failure(error):
                    downstream.receive(completion: .failure(error))
                    self.parent = nil // terminate
                }
            }
            
            private func didRecieve(_ value: Output) {
                
                guard demand > 0,
                    let downstream = self.downstream else {
                    return
                }
                demand -= 1
                let newDemand = downstream.receive(value)
                demand += newDemand
            }
            
            func request(_ demand: Subscribers.Demand) {
                self.demand += demand
            }
            
            func cancel() {
                
                guard let parent = self.parent
                    else { return }
                parent.central.notify(nil, for: parent.characteristic, timeout: parent.timeout, completion: { _ in })
                self.parent = nil
            }
        }
    }
}

// MARK: - Extensions

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Subscribers.Demand {
    internal func assertNonZero(file: StaticString = #file,
                                line: UInt = #line) {
        if self == .none {
            fatalError("API Violation: demand must not be zero", file: file, line: line)
        }
    }
}

#endif
