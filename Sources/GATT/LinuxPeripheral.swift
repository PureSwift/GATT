//
//  LinuxPeripheral.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/2/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

#if os(Linux) || (Xcode && SWIFT_PACKAGE)
    
    import Foundation
    import Bluetooth
    import BluetoothLinux
    
    @available(OSX 10.12, *)
    public final class LinuxPeripheral: PeripheralProtocol {
        
        // MARK: - Properties
        
        public var log: ((String) -> ())?
        
        public let options: Options
        
        public let controller: HostController
        
        public var willRead: ((GATTReadRequest) -> ATT.Error?)?
        
        public var willWrite: ((GATTWriteRequest) -> ATT.Error?)?
        
        public var didWrite: ((GATTWriteConfirmation) -> ())?
        
        // MARK: - Private Properties
        
        fileprivate var database = GATTDatabase()
        
        fileprivate var isServerRunning = false
        
        fileprivate var serverSocket: L2CAPSocket?
        
        fileprivate var serverThread: Thread?
        
        fileprivate var clients = [Client]()
        
        private var lastConnectionID = 0
        
        // MARK: - Initialization
        
        public init(controller: HostController,
                    options: Options = Options()) {
            
            self.controller = controller
            self.options = options
        }
        
        // MARK: - Methods
        
        public func start() throws {
            
            guard isServerRunning == false else { return }
            
            // enable advertising
            do { try controller.enableLowEnergyAdvertising() }
            catch HCIError.commandDisallowed { /* ignore */ }
            
            let serverSocket = try L2CAPSocket.lowEnergyServer(controllerAddress: controller.address,
                                                               isRandom: false,
                                                               securityLevel: .low)
            
            isServerRunning = true
            
            log?("Started GATT Server")
            
            let serverThread = Thread { [weak self] in self?.main() }
            
            self.serverSocket = serverSocket
            self.serverThread = serverThread
            
            serverThread.start()
        }
        
        public func stop() {
            
            guard isServerRunning else { return }
            
            isServerRunning = false
            
            self.serverSocket = nil
            self.serverThread = nil
        }
        
        public func add(service: GATT.Service) throws -> UInt16 {
            
            return database.add(service: service)
        }
        
        public func remove(service handle: UInt16) {
            
            database.remove(service: handle)
        }
        
        public func removeAllServices() {
            
            database.removeAll()
        }
        
        /// Return the handles of the characteristics matching the specified UUID.
        public func characteristics(for uuid: BluetoothUUID) -> [UInt16] {
            
            return database.filter { $0.uuid == uuid }.map { $0.handle }
        }
        
        // MARK: - Private Methods
        
        private func main() {
            
            guard let serverSocket = self.serverSocket
                else { fatalError("No server socket") }
            
            while isServerRunning {
                
                do {
                    
                    let newSocket = try serverSocket.waitForConnection()
                    
                    guard isServerRunning else { return }
                    
                    log?("[\(newSocket.address)]: New \(newSocket.addressType) connection")
                    
                    let client = Client(socket: newSocket, peripheral: self)
                    
                    clients.append(client)
                }
                    
                catch { log?("Error waiting for new connection: \(error)") }
            }
            
            log?("Stopped GATT Server")
        }
        
        fileprivate func newConnectionID() -> Int {
            
            lastConnectionID += 1
            
            return lastConnectionID
        }
        
        // MARK: Subscript
        
        public subscript(characteristic handle: UInt16) -> Data {
            
            get { return database[handle: handle].value }
            
            set { clients.forEach { $0.server.writeValue(newValue, forCharacteristic: handle) } }
        }
    }
    
    @available(OSX 10.12, *)
    public extension LinuxPeripheral {
        
        public struct Options {
            
            public let maximumTransmissionUnit: ATTMaximumTransmissionUnit
            
            public let maximumPreparedWrites: Int
            
            public init(maximumTransmissionUnit: ATTMaximumTransmissionUnit = .default,
                        maximumPreparedWrites: Int = 100) {
                
                self.maximumTransmissionUnit = maximumTransmissionUnit
                self.maximumPreparedWrites = maximumPreparedWrites
            }
        }
    }
    
    @available(OSX 10.12, *)
    private extension LinuxPeripheral {
        
        final class Client {
            
            let connectionID: Int
            
            let central: Central
            
            let server: GATTServer
            
            lazy var thread: Thread = Thread { [weak self] in self?.main() }
            
            private(set) weak var peripheral: LinuxPeripheral!
            
            private var maximumUpdateValueLength: Int {
                
                // ATT_MTU-3
                return Int(server.maximumTransmissionUnit.rawValue) - 3
            }
            
            init(socket: L2CAPSocket, peripheral: LinuxPeripheral) {
                
                // initialize
                self.peripheral = peripheral
                self.connectionID = peripheral.newConnectionID()
                self.central = Central(socket: socket)
                self.server = GATTServer(socket: socket,
                                         maximumTransmissionUnit: peripheral.options.maximumTransmissionUnit,
                                         maximumPreparedWrites: peripheral.options.maximumPreparedWrites)
                
                // start running
                server.database = peripheral.database
                server.log = { [unowned self] in self.peripheral.log?("[\(self.central)]: " + $0) }
                
                server.willRead = { [unowned self] (uuid, handle, value, offset) in
                    
                    let request = GATTReadRequest(central: self.central,
                                                  maximumUpdateValueLength: self.maximumUpdateValueLength,
                                                  uuid: uuid,
                                                  handle: handle,
                                                  value: value,
                                                  offset: offset)
                    
                    return self.peripheral.willRead?(request)
                }
                
                server.willWrite = { [unowned self] (uuid, handle, value, newValue) in
                    
                    let request = GATTWriteRequest(central: self.central,
                                                   maximumUpdateValueLength: self.maximumUpdateValueLength,
                                                   uuid: uuid,
                                                   handle: handle,
                                                   value: value,
                                                   newValue: newValue)
                    
                    return self.peripheral.willWrite?(request)
                }
                
                server.didWrite = { [unowned self] (uuid, handle, newValue) in
                    
                    let confirmation = GATTWriteConfirmation(central: self.central,
                                                             maximumUpdateValueLength: self.maximumUpdateValueLength,
                                                             uuid: uuid,
                                                             handle: handle,
                                                             value: newValue)
                    
                    self.peripheral.didWrite?(confirmation)
                }
                
                thread.start()
            }
            
            private func main() {
                
                while let peripheral = self.peripheral, peripheral.isServerRunning {
                    
                    do {
                        
                        server.database = peripheral.database
                        
                        try server.read()
                        
                        peripheral.database = server.database
                        
                        /// write outgoing pending ATT PDUs
                        var didWrite = false
                        repeat { didWrite = try server.write() }
                        while didWrite
                    }
                    
                    catch {
                        
                        peripheral.log?("[\(central)]: Disconnected \(error)")
                        
                        do { try peripheral.controller.enableLowEnergyAdvertising() }
                        catch HCIError.commandDisallowed { /* ignore */ }
                        catch { fatalError("Could not enable advertising.") }
                        
                        break // end while loop
                    }
                }
                
                // remove from peripheral
                guard let index = self.peripheral?.clients.index(where: { $0.connectionID == connectionID })
                    else { return }
                
                self.peripheral?.clients.remove(at: index)
            }
        }
    }

#endif

#if os(Linux)

    /// The platform specific peripheral.
    public typealias PeripheralManager = LinuxPeripheral

#endif
