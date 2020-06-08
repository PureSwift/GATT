//
//  DarwinCombineCentral.swift
//  
//
//  Created by Alsey Coleman Miller on 6/6/20.
//

import Foundation
import Bluetooth
import GATT

#if canImport(CoreBluetooth) && (canImport(Combine) || canImport(OpenComine))
import CoreBluetooth
#if canImport(Combine)
import Combine
#elseif canImport(OpenCombine)
import OpenCombine
#endif

/// CoreBluetooth GATT Central Manager
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public final class DarwinCombineCentral { //: CombineCentral {
    
    // MARK: - Properties
    
    /// TODO: Improve logging API, use Logger?
    public let log = PassthroughSubject<String, Error>()
    
    @Published
    public private(set) var isScanning = false
    
    @Published
    public private(set) var state: DarwinBluetoothState = .unknown
    
    @Published
    public private(set) var peripherals = [Peripheral: Advertisement]()
    
    /// CoreBluetooth Central Manager Options
    public let options: Options
    
    internal lazy var internalManager = CBCentralManager(
        delegate: self.delegate,
        queue: self.managerQueue,
        options: self.options.optionsDictionary
    )
    
    internal lazy var managerQueue = DispatchQueue(label: "\(type(of: self)) Manager Queue")
    
    internal lazy var queue = DispatchQueue(label: "\(type(of: self)) Queue")
    
    internal lazy var delegate = Delegate(self)

    internal private(set) var cache = Cache()
    
    internal private(set) var combine = Combine()
    
    // MARK: - Initialization
    
    /// Initialize with the specified options.
    ///
    /// - Parameter options: An optional dictionary containing initialization options for a central manager.
    /// For available options, see [Central Manager Initialization Options](apple-reference-documentation://ts1667590).
    public init(options: Options = Options()) {
        self.options = options
        _ = self.internalManager // initialize
    }
    
    // MARK: - Methods
    
    public func devices() -> Deferred<PassthroughSubject<Set<Peripheral>, Error>> {
        //self.internalManager.retrievePeripherals()
        fatalError()
    }
    
    /// Scans for peripherals that are advertising services.
    public func scan(filterDuplicates: Bool) -> PassthroughSubject<ScanData<Peripheral, Advertisement>, Error> {
        
        return self.scan(filterDuplicates: filterDuplicates, with: [])
    }
    
    /// Scans for peripherals that are advertising services.
    public func scan(filterDuplicates: Bool,
                     with services: Set<BluetoothUUID>) -> PassthroughSubject<ScanData<Peripheral, Advertisement>, Error> {
                        
        let serviceUUIDs: [CBUUID]? = services.isEmpty ? nil : services.map { CBUUID($0) }
        
        let options: [String: Any] = [
            CBCentralManagerScanOptionAllowDuplicatesKey: NSNumber(value: filterDuplicates == false)
        ]
        
        queue.async { [unowned self] in
            precondition(self.internalManager.isScanning == false)
            do {
                let state = self.state
                guard state == .poweredOn
                    else { throw DarwinCentralError.invalidState(state) }
                self.log.send("Scanning...")
                self.combine = .init()
                // start scanning
                self.internalManager.scanForPeripherals(withServices: serviceUUIDs, options: options)
                assert(self.internalManager.isScanning)
            } catch {
                self.combine.scan.send(completion: .failure(error))
            }
        }
        
        return combine.scan
    }
    
    /// Stops scanning for peripherals.
    func stopScan() {
        queue.async { [unowned self] in
            assert(self.internalManager.isScanning)
            defer { assert(self.internalManager.isScanning == false) }
            self.internalManager.stopScan()
            self.combine.scan.send(completion: .finished)
            self.log.send("Discovered \(self.cache.peripherals.count) peripherals")
        }
    }
    
    /// Connect to the specifed peripheral.
    /// - Parameter peripheral: The peripheral to which the central is attempting to connect.
    /// - Parameter options: A dictionary to customize the behavior of the connection.
    /// For available options, see [Peripheral Connection Options](apple-reference-documentation://ts1667676).
    public func connect(to peripheral: Peripheral, timeout: TimeInterval, options: [String: Any]) -> Future<Void, Error> {
        
        
        
        let future = Future<Void, Error> { [unowned self] (completion) in
            
            let subject = CurrentValueSubject(
            
            self.queue.async {
                do {
                    let state = self.state
                    guard state == .poweredOn
                        else { throw DarwinCentralError.invalidState(state) }
                    let corePeripheral = try self.peripheral(for: peripheral)
                    assert(corePeripheral.state != .connected)
                    self.combine.connect[peripheral] = completion
                    // attempt to connect (does not timeout)
                    self.internalManager.connect(corePeripheral, options: options)
                }
                catch {
                    completion(.failure(error))
                    self.combine.connect[peripheral] = nil
                }
            }
            
            self.queue.asyncAfter(deadline: <#T##DispatchTime#>, execute: <#T##() -> Void#>)
        }
        
        return future
        
        
        
        guard let corePeripheral = accessQueue.sync(execute: { [unowned self] in self.peripheral(peripheral) })
            else { throw CentralError.unknownPeripheral }
        
        guard corePeripheral.state != .connected
            else { return } // already connected
        
        // store semaphore
        let semaphore = Semaphore(timeout: timeout, operation: .connect(peripheral))
        accessQueue.sync { [unowned self] in self.internalState.connect.semaphore = semaphore }
        defer { accessQueue.sync { [unowned self] in self.internalState.connect.semaphore = nil } }
        
        // attempt to connect (does not timeout)
        self.internalManager.connect(corePeripheral, options: options)
        
        // throw async error
        do { try semaphore.wait() }
            
        catch CentralError.timeout {
            
            // cancel connection if we timeout
            self.internalManager.cancelPeripheralConnection(corePeripheral)
            throw CentralError.timeout
        }
        
        assert(corePeripheral.state == .connected, "Peripheral should be connected")
    }
    
    /// Disconnect from the speciffied peripheral.
    func disconnect(peripheral: Peripheral) {
        
    }
    
    /// Disconnect from all connected peripherals.
    func disconnectAll() {
        URLSession.shared.dataTaskPublisher(for: <#T##URL#>)
    }
    
    /// Discover the specified services.
    func discoverServices(_ services: [BluetoothUUID],
                          for peripheral: Peripheral,
                          timeout: TimeInterval) -> PassthroughSubject<Service<Peripheral>, Error> {
        
    }
    
    /// Discover characteristics for the specified service.
    func discoverCharacteristics(_ characteristics: [BluetoothUUID],
                                for service: Service<Peripheral>,
                                timeout: TimeInterval) -> PassthroughSubject<[Characteristic<Peripheral>], Error> {
        
    }
    
    /// Read characteristic value.
    func readValue(for characteristic: Characteristic<Peripheral>,
                   timeout: TimeInterval) -> PassthroughSubject<Data, Error> {
        
    }
    
    /// Write characteristic value.
    func writeValue(_ data: Data,
                    for characteristic: Characteristic<Peripheral>,
                    withResponse: Bool,
                    timeout: TimeInterval) -> PassthroughSubject<Void, Error> {
        
    }
    
    /// Subscribe to notifications for the specified characteristic.
    func notify(for characteristic: Characteristic<Peripheral>,
                timeout: TimeInterval) -> PassthroughSubject<Data, Error> {
        
    }
    
    /// Stop subcribing to notifications.
    func stopNotification(for characteristic: Characteristic<Peripheral>,
                          timeout: TimeInterval) -> PassthroughSubject<Void, Error> {
        
    }
    
    /// Get the maximum transmission unit for the specified peripheral.
    func maximumTransmissionUnit(for peripheral: Peripheral) -> PassthroughSubject<ATTMaximumTransmissionUnit, Error> {
        
        let future = Future<ATTMaximumTransmissionUnit, Error>()
        self.accessQueue.async {
            do {
                guard state == .poweredOn
                    else { throw DarwinCentralError.invalidState(state) }
                
            }
            catch {
                
            }
        }
        return subject
        
        
        
        let corePeripheral = try accessQueue.sync { [unowned self] in
            try self.connectedPeripheral(peripheral)
        }
        
        let mtu = corePeripheral.maximumWriteValueLength(for: .withoutResponse) + 3
        assert((corePeripheral.value(forKey: "mtuLength") as! NSNumber).intValue == mtu)
        return ATTMaximumTransmissionUnit(rawValue: UInt16(mtu)) ?? .default
    }
    
    // MARK: - Private Methods
    
    internal func peripheral(for peripheral: Peripheral) throws -> CBPeripheral {
        guard let corePeripheral = self.cache.peripherals[peripheral]
            else { throw CentralError.unknownPeripheral }
        return corePeripheral
    }
}

// MARK: - Supporting Types

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public extension DarwinCombineCentral {
    
    typealias Advertisement = DarwinAdvertisementData
    
    typealias State = DarwinBluetoothState
    
    /// Central Peer
    ///
    /// Represents a remote central device that has connected to an app implementing the peripheral role on a local device.
    struct Peripheral: Peer {
        
        public let identifier: UUID
        
        internal init(_ peripheral: CBPeripheral) {
            self.identifier = peripheral.gattIdentifier
        }
    }
    
    /**
     Darwin GATT Central Options
     */
    struct Options {
        
        /**
         A Boolean value that specifies whether the system should display a warning dialog to the user if Bluetooth is powered off when the peripheral manager is instantiated.
         */
        public let showPowerAlert: Bool
        
        /**
         A string (an instance of NSString) containing a unique identifier (UID) for the peripheral manager that is being instantiated.
         The system uses this UID to identify a specific peripheral manager. As a result, the UID must remain the same for subsequent executions of the app in order for the peripheral manager to be successfully restored.
         */
        public let restoreIdentifier: String?
        
        /**
         Initialize options.
         */
        public init(showPowerAlert: Bool = false,
                    restoreIdentifier: String? = nil) {
            
            self.showPowerAlert = showPowerAlert
            self.restoreIdentifier = restoreIdentifier
        }
        
        internal var optionsDictionary: [String: Any] {
            
            var options = [String: Any](minimumCapacity: 2)
            if showPowerAlert {
                options[CBPeripheralManagerOptionShowPowerAlertKey] = showPowerAlert as NSNumber
            }
            options[CBPeripheralManagerOptionRestoreIdentifierKey] = restoreIdentifier
            return options
        }
    }
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
internal extension DarwinCombineCentral {
    
    @objc(DarwinCombineCentralDelegate)
    final class Delegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
        
        private(set) weak var central: DarwinCombineCentral!
        
        fileprivate init(_ central: DarwinCombineCentral) {
            super.init()
            self.central = central
        }
        
        // MARK: - CBCentralManagerDelegate
        
        func centralManagerDidUpdateState(_ centralManager: CBCentralManager) {
            assert(self.central != nil)
            assert(self.central?.internalManager === centralManager)
            let state = unsafeBitCast(central!.state, to: DarwinBluetoothState.self)
            self.central?.log.send("Did update state \(state)")
            self.central?.state = state
        }
        
        func centralManager(_ centralManager: CBCentralManager, willRestoreState dict: [String : Any]) {
            assert(self.central != nil)
            assert(self.central?.internalManager === centralManager)
            // TODO: Restore state
            //let peripherals = centralManager.retrievePeripherals(withIdentifiers: )
        }
        
        func centralManager(_ centralManager: CBCentralManager,
                            didDiscover peripheral: CBPeripheral,
                            advertisementData: [String : Any], rssi: NSNumber) {
            
            assert(self.central != nil)
            assert(self.central?.internalManager === centralManager)
            
            let identifier = Peripheral(peripheral)
            let advertisement = Advertisement(advertisementData)
            let scanResult = ScanData(peripheral: identifier,
                                      date: Date(),
                                      rssi: rssi.doubleValue,
                                      advertisementData: advertisement,
                                      isConnectable: advertisement.isConnectable ?? false)
            
            self.central.queue.async {
                self.central.combine.scan.send(scanResult)
            }
        }
        
        @objc(centralManager:didConnectPeripheral:)
        public func centralManager(_ centralManager: CBCentralManager, didConnect corePeripheral: CBPeripheral) {
            
            log?("Did connect to peripheral \(corePeripheral.gattIdentifier.uuidString)")
            
            assert(corePeripheral.state != .disconnected, "Should be connected")
            assert(self.central != nil)
            assert(self.central?.internalManager === centralManager)
            
            queue.sync { [unowned self] in
                let peripheral = Peripheral(corePeripheral)
                guard completion = self.central.combine.connect[peripheral]
                    else { assertionFailure("Missing subject"); return }
                
                completion(.success)
                self.internalState.connect.semaphore?.stopWaiting()
                self.internalState.connect.semaphore = nil
                self.internalState.cache[Peripheral(corePeripheral)] = Cache() // initialize cache
            }
        }
        
        @objc(centralManager:didFailToConnectPeripheral:error:)
        public func centralManager(_ central: CBCentralManager, didFailToConnect corePeripheral: CBPeripheral, error: Swift.Error?) {
            
            log?("Did fail to connect to peripheral \(corePeripheral.gattIdentifier.uuidString) (\(error!))")
            
            accessQueue.sync { [unowned self] in
                self.internalState.connect.semaphore?.stopWaiting(error)
                self.internalState.connect.semaphore = nil
            }
        }
        
        @objc(centralManager:didDisconnectPeripheral:error:)
        public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral corePeripheral: CBPeripheral, error: Swift.Error?) {
            
            let peripheral = Peripheral(corePeripheral)
            
            if let error = error {
                log?("Did disconnect peripheral \(corePeripheral.gattIdentifier.uuidString) due to error \(error.localizedDescription)")
            } else {
                log?("Did disconnect peripheral \(corePeripheral.gattIdentifier.uuidString)")
            }
            
            self.didDisconnect?(peripheral)
            
            // cancel all actions that require an active connection
            let semaphores = [
                internalState.discoverServices.semaphore,
                internalState.discoverCharacteristics.semaphore,
                internalState.writeCharacteristic.semaphore,
                internalState.flushWriteWithoutResponse.semaphore,
                internalState.readCharacteristic.semaphore,
                internalState.notify.semaphore
            ]
            
            semaphores
                .filter { $0?.operation.peripheral == peripheral }
                .compactMap { $0 }
                .forEach { $0.stopWaiting(CentralError.disconnected) }
        }
        
        // MARK: - CBPeripheralDelegate
        
        
    }
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
internal extension DarwinCombineCentral {
    
    struct Cache {
        var peripherals = [Peripheral: CBPeripheral]()
        var advertisementData = [Peripheral: Advertisement]()
    }
    
    struct Combine {
        
        let scan = PassthroughSubject<ScanData<Peripheral, Advertisement>, Error>()
        var connect = [Peripheral: ((Result<Void, Error>) -> ())]()
    }
    
    struct PeripheralCache {
        var advertisement: DarwinAdvertisementData
        
    }
    
    
    }
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public extension DarwinCombineCentral {
    
    
}

public struct GATTPublisher<Peripheral: Peer, Output>: Publisher {
    
    
    /// The kind of values published by this publisher.
    public typealias Output = (data: Data, response: URLResponse)

    /// The kind of errors this publisher might publish.
    ///
    /// Use `Never` if this `Publisher` does not publish errors.
    public typealias Failure = URLError

    public let timeout: TimeInterval

    public let peripheral: Peripheral

    public init(timeout: TimeInterval, peripheral: Peripheral, operation: )

    /// This function is called to attach the specified `Subscriber` to this `Publisher` by `subscribe(_:)`
    ///
    /// - SeeAlso: `subscribe(_:)`
    /// - Parameters:
    ///     - subscriber: The subscriber to attach to this `Publisher`.
    ///                   once attached it can begin to receive values.
    public func receive<S>(subscriber: S) where S : Subscriber, S.Failure == URLSession.DataTaskPublisher.Failure, S.Input == URLSession.DataTaskPublisher.Output
}

#endif
