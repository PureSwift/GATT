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
    public private(set) var peripherals = Set<Peripheral>()
    
    /// CoreBluetooth Central Manager Options
    public let options: Options
    
    private lazy var internalManager = CBCentralManager(
        delegate: self.delegate,
        queue: self.managerQueue,
        options: self.options.optionsDictionary
    )
    
    private lazy var managerQueue = DispatchQueue(label: "\(type(of: self)) Manager Queue")
    
    private lazy var queue = DispatchQueue(label: "\(type(of: self)) Queue")
    
    private var peripheralQueue = [Peripheral: DispatchQueue]()
    
    private lazy var delegate = Delegate(self)

    private var cache = Cache()
    
    private var combine = Combine()
    
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
    
    /// Scans for peripherals that are advertising services.
    public func scan(filterDuplicates: Bool) -> AnyPublisher<ScanData<Peripheral, Advertisement>, Error> {
        
        return self.scan(filterDuplicates: filterDuplicates, with: [])
    }
    
    /// Scans for peripherals that are advertising services.
    public func scan(filterDuplicates: Bool,
                     with services: Set<BluetoothUUID>) -> AnyPublisher<ScanData<Peripheral, Advertisement>, Error> {
                        
        let serviceUUIDs: [CBUUID]? = services.isEmpty ? nil : services.map { CBUUID($0) }
        
        let options: [String: Any] = [
            CBCentralManagerScanOptionAllowDuplicatesKey: NSNumber(value: filterDuplicates == false)
        ]
        
        return self.centralManager.tryMap { [unowned self] (central) in
            self.combine = .init()
            self.peripheralQueue.removeAll(keepingCapacity: true)
            self.peripherals.removeAll(keepingCapacity: true)
            precondition(central.isScanning == false)
            guard self.state == .poweredOn
                else { throw DarwinCentralError.invalidState(self.state) }
            self.log.send("Scanning...")
            central.scanForPeripherals(withServices: serviceUUIDs, options: options)
            assert(central.isScanning)
        }
        .flatMap { self.combine.scan }
        .eraseToAnyPublisher()
    }
    
    /// Stops scanning for peripherals.
    public func stopScan() {
        let _ = self.centralManager.sink {
            assert($0.isScanning)
            $0.stopScan()
            assert($0.isScanning == false)
            self.combine.scan.send(completion: .finished)
            self.log.send("Discovered \(self.cache.peripherals.count) peripherals")
        }
    }
    
    /// Connect to the specifed peripheral.
    /// - Parameter peripheral: The peripheral to which the central is attempting to connect.
    /// - Parameter options: A dictionary to customize the behavior of the connection.
    /// For available options, see [Peripheral Connection Options](apple-reference-documentation://ts1667676).
    public func connect(to peripheral: Peripheral,
                        options: [String: Any]) -> AnyPublisher<ConnectionState, Error> {
        
        let subject = CurrentValueSubject<ConnectionState, Error>(.disconnected)
        return self.centralManager.tryMap { [unowned self] (central) -> CBCentralManager in
            guard self.state == .poweredOn else { throw DarwinCentralError.invalidState(self.state) }
            self.combine.connect[peripheral] = subject
            return central
        }
        .combineLatest(self.peripheral(for: peripheral))
        .tryMap { (central, peripheral) in
            assert(peripheral.state != .connected)
            // attempt to connect (does not timeout)
            central.connect(peripheral, options: options)
        }
        .flatMap { subject }
        .eraseToAnyPublisher()
    }
    
    /// Cancels an active or pending local connection to a peripheral.
    ///
    /// - Parameter The peripheral to which the central manager is either trying to connect or has already connected.
    internal func cancelConnection(for peripheral: Peripheral) {
        self.queue.async {
            self.cache.peripherals[peripheral].flatMap {
                self.internalManager.cancelPeripheralConnection($0)
            }
        }
    }
    
    /// Disconnect from the speciffied peripheral.
    public func disconnect(peripheral: Peripheral) {
        cancelConnection(for: peripheral)
    }
    
    /// Disconnect from all connected peripherals.
    public func disconnectAll() {
        self.queue.async { [unowned self] in
            self.cache.peripherals
                .values
                .forEach { self.internalManager.cancelPeripheralConnection($0) }
        }
    }
    
    /// Discover the specified services.
    public func discoverServices(_ services: [BluetoothUUID],
                          for peripheral: Peripheral) -> AnyPublisher<[Service<Peripheral, AttributeID>], Error> {
        
        let subject = PassthroughSubject<[Service<Peripheral, AttributeID>], Error>()
        let coreServices = services.isEmpty ? nil : services.map { CBUUID($0) }
        
        return self.centralManager.tryMap { [unowned self] (central) -> CBCentralManager in
            guard self.state == .poweredOn else { throw DarwinCentralError.invalidState(self.state) }
            self.combine.services[peripheral] = subject
            return central
        }
        .combineLatest(self.peripheral(for: peripheral))
        .tryMap { (central, peripheral) in
            guard peripheral.state == .connected
                else { throw CentralError.disconnected }
            
            // attempt to connect (does not timeout)
            central.connect(peripheral, options: options)
        }.eraseToAnyPublisher()
        
        self.centralManager.
        centralManager { [unowned self] (central) in
            do {
                // store subject for completion
                self.combine.services[peripheral] = subject
                // validate state
                let state = self.state
                guard state == .poweredOn
                    else { throw DarwinCentralError.invalidState(state) }
                self.peripheral(for: peripheral) { (corePeripheral) in
                    corePeripheral.discoverServices(coreServices)
                }
                
                let corePeripheral = try self.peripheral(for: peripheral)
                guard corePeripheral.state == .connected
                    else { throw CentralError.disconnected }
                // store subject for completion
                self.combine.services[peripheral] = subject
                // interact with peripheral on separate queue
                self.queue(for: peripheral).async {
                    // start discovery
                    
                }
            }
            catch {
                subject.send(completion: .failure(error))
            }
        }
        
        return subject.eraseToAnyPublisher()
    }
    
    /// Discover characteristics for the specified service.
    func discoverCharacteristics(_ characteristics: [BluetoothUUID],
                                for service: Service<Peripheral, AttributeID>,
                                timeout: TimeInterval) -> PassthroughSubject<[Characteristic<Peripheral, AttributeID>], Error> {
        
        
    }
    
    /// Read characteristic value.
    func readValue(for characteristic: Characteristic<Peripheral, AttributeID>,
                   timeout: TimeInterval) -> PassthroughSubject<Data, Error> {
        
    }
    
    /// Write characteristic value.
    func writeValue(_ data: Data,
                    for characteristic: Characteristic<Peripheral, AttributeID>,
                    withResponse: Bool,
                    timeout: TimeInterval) -> PassthroughSubject<Void, Error> {
        
    }
    
    /// Subscribe to notifications for the specified characteristic.
    func notify(for characteristic: Characteristic<Peripheral, AttributeID>,
                timeout: TimeInterval) -> PassthroughSubject<Data, Error> {
        
    }
    
    /// Stop subcribing to notifications.
    func stopNotification(for characteristic: Characteristic<Peripheral, AttributeID>,
                          timeout: TimeInterval) -> PassthroughSubject<Void, Error> {
        
    }
    
    /// Get the maximum transmission unit for the specified peripheral.
    func maximumTransmissionUnit(for peripheral: Peripheral) -> AnyPublisher<ATTMaximumTransmissionUnit, Error> {
        
        return self.centralManager.tryMap { _ in
            guard self.state == .poweredOn else { throw DarwinCentralError.invalidState(self.state) }
        }
        .flatMap { _ in
            self.peripheral(for: peripheral)
        }
        .tryMap {
            let mtu = $0.maximumWriteValueLength(for: .withoutResponse) + 3
            assert(($0.value(forKey: "mtuLength") as! NSNumber).intValue == mtu)
            return ATTMaximumTransmissionUnit(rawValue: UInt16(mtu)) ?? .default
        }
        .eraseToAnyPublisher()
    }
    
    // MARK: - Private Methods
    
    private lazy var centralManager: AnyPublisher<CBCentralManager, Never> = Just(self.internalManager)
            .receive(on: self.queue)
            .eraseToAnyPublisher()
    
    private func peripheral(for peripheral: Peripheral) -> AnyPublisher<CBPeripheral, Error> {
        return self.centralManager.tryMap { _ in
            if let corePeripheral = self.cache.peripherals[peripheral] {
                return corePeripheral
            } else {
                throw CentralError.unknownPeripheral
            }
        }
        .receive(on: queue(for: peripheral))
        .eraseToAnyPublisher()
    }
    
    private func queue(for peripheral: Peripheral) -> DispatchQueue {
        return self.peripheralQueue[peripheral, default: DispatchQueue(label: "Peripheral \(peripheral) Queue")]
    }
}

// MARK: - Supporting Types

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public extension DarwinCombineCentral {
    
    typealias Advertisement = DarwinAdvertisementData
    
    typealias State = DarwinBluetoothState
    
    typealias AttributeID = ObjectIdentifier
    
    enum ConnectionState {
        case connecting
        case connected
        case disconnected
    }
    
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
            let state = unsafeBitCast(centralManager.state, to: DarwinBluetoothState.self)
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
                self.central.cache.peripherals[identifier] = peripheral
                self.central.peripherals.insert(identifier)
                self.central.combine.scan.send(scanResult)
            }
        }
        
        @objc(centralManager:didConnectPeripheral:)
        public func centralManager(_ centralManager: CBCentralManager, didConnect corePeripheral: CBPeripheral) {
            
            self.central?.log.send("Did connect to peripheral \(corePeripheral.gattIdentifier.uuidString)")
            
            assert(corePeripheral.state != .disconnected, "Should be connected")
            assert(self.central != nil)
            assert(self.central?.internalManager === centralManager)
            
            self.central.queue.sync { [unowned self] in
                let peripheral = Peripheral(corePeripheral)
                guard let subject = self.central.combine.connect[peripheral]
                    else { assertionFailure("Missing subject"); return }
                subject.send(true)
            }
        }
        
        @objc(centralManager:didFailToConnectPeripheral:error:)
        public func centralManager(_ centralManager: CBCentralManager, didFailToConnect corePeripheral: CBPeripheral, error: Swift.Error?) {
            
            self.central?.log.send("Did fail to connect to peripheral \(corePeripheral.gattIdentifier.uuidString) (\(error!))")
            
            assert(corePeripheral.state != .disconnected, "Should be connected")
            assert(self.central != nil)
            assert(self.central?.internalManager === centralManager)
            assert(error != nil)
            
            self.central.queue.sync { [unowned self] in
                let peripheral = Peripheral(corePeripheral)
                guard let subject = self.central.combine.connect[peripheral]
                    else { assertionFailure("Missing subject"); return }
                subject.send(completion: .failure(error!))
            }
        }
        
        @objc(centralManager:didDisconnectPeripheral:error:)
        public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral corePeripheral: CBPeripheral, error: Swift.Error?) {
                        
            if let error = error {
                self.central?.log.send("Did disconnect peripheral \(corePeripheral.gattIdentifier.uuidString) due to error \(error.localizedDescription)")
            } else {
                self.central?.log.send("Did disconnect peripheral \(corePeripheral.gattIdentifier.uuidString)")
            }
            
            self.central.queue.sync { [unowned self] in
                let peripheral = Peripheral(corePeripheral)
                guard let subject = self.central.combine.connect[peripheral]
                    else { assertionFailure("Missing subject"); return }
                if let error = error {
                    subject.send(completion: .failure(error))
                } else {
                    subject.send(false)
                }
            }
            
            // cancel all actions that require an active connection
            /*
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
            */
        }
        
        // MARK: - CBPeripheralDelegate
        
        func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
            
            
        }
    }
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
internal extension DarwinCombineCentral {
    
    struct Cache {
        var peripherals = [Peripheral: CBPeripheral]()
    }
    
    struct Combine {
        
        let scan = PassthroughSubject<ScanData<Peripheral, Advertisement>, Error>()
        var connect = [Peripheral: CurrentValueSubject<ConnectionState, Error>]()
        var services = [Peripheral: PassthroughSubject<[Service<Peripheral, AttributeID>], Error>]()
    }
}

#endif
