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
import GATT

#if canImport(Combine) || canImport(OpenCombine)

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public final class DarwinCombineCentral: CombineCentral<DarwinCentral> {
    
    @Published
    public var state: DarwinBluetoothState = .unknown
    
    public convenience init(options: DarwinCentral.Options = .init()) {
        let central = DarwinCentral(options: options)
        self.init(central: central)
        central.stateChanged = { [weak self] in self?.state = $0 }
        self.state = central.state
    }
    
    /// Scans for peripherals that are advertising services.
    public func scan(filterDuplicates: Bool, with services: Set<BluetoothUUID>) -> DarwinScanPublisher {
        return DarwinScanPublisher(central: central, filterDuplicates: filterDuplicates, services: services)
    }
    
    /// GATT Scan Publisher
    public struct DarwinScanPublisher: Publisher {
        
        public typealias Output = ScanData<Peripheral, Advertisement>
        
        public typealias Failure = Error
        
        public let central: DarwinCentral
        
        public let filterDuplicates: Bool
        
        public let services: Set<BluetoothUUID>
        
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
            
            private var parent: DarwinScanPublisher?
            
            private var downstream: Downstream?
            
            private var demand = Subscribers.Demand.none
            
            fileprivate init(parent: DarwinScanPublisher,
                             downstream: Downstream) {
                
                self.parent = parent
                self.downstream = downstream
                
                // start scanning
                parent.central.scan(filterDuplicates: parent.filterDuplicates, with: parent.services) { [weak self] in
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
}

#endif
