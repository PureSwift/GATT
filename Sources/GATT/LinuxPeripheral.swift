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
        
        public var willRead: ((PeripheralReadRequest) -> ATT.Error?)?
        
        public var willWrite: ((PeripheralWriteRequest) -> ATT.Error?)?
        
        public var didWrite: ((PeripheralWriteRequest) -> ())?
        
        // MARK: - Private Properties
        
        fileprivate var database = GATTDatabase()
        
        fileprivate var isServerRunning = false
        
        fileprivate var serverSocket: L2CAPSocket?
        
        fileprivate var serverThread: Thread?
        
        fileprivate var centrals = [Central]()
        
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
            
            let serverThread = Thread(block: { [weak self] in
                
                guard let peripheral = self else { return }
                
                while peripheral.isServerRunning {
                    
                    do {
                        
                        let newSocket = try serverSocket.waitForConnection()
                        
                        guard peripheral.isServerRunning else { return }
                        
                        peripheral.log?("New \(newSocket.addressType) connection from \(newSocket.address)")
                        
                        let server = GATTServer(socket: newSocket)
                        
                        server.log = { peripheral.log?("[\(newSocket.address)]: " + $0) }
                        
                        server.database = peripheral.database
                        
                        // create new thread for new connection
                        
                        let newConnectionThread = Thread(block: {
                            
                            while peripheral.isServerRunning {
                                
                                // ATT_MTU-3
                                let maximumUpdateValueLength = Int(server.maximumTransmissionUnit.rawValue) - 3
                                
                                let central = Central(socket: newSocket)
                                
                                do {
                                    
                                    var didWriteValues: PeripheralWriteRequest?
                                    
                                    server.willRead = { (uuid, handle, value, offset)  in
                                        
                                        let request = PeripheralReadRequest(central: central,
                                                                            maximumUpdateValueLength: maximumUpdateValueLength,
                                                                            uuid: uuid,
                                                                            handle: handle,
                                                                            value: value,
                                                                            offset: offset)
                                        
                                        return peripheral.willRead?(request)
                                    }
                                    
                                    server.willWrite = { (uuid, handle, value, newValue) in
                                        
                                        let request = PeripheralWriteRequest(central: central,
                                                                            maximumUpdateValueLength: maximumUpdateValueLength,
                                                                            uuid: uuid,
                                                                            handle: handle,
                                                                            value: value,
                                                                            newValue: newValue)
                                        
                                        if let error = peripheral.willWrite?(request) {
                                            
                                            return error
                                        }
                                        
                                        didWriteValues = request
                                        
                                        return nil
                                    }
                                    
                                    server.database = peripheral.database
                                    
                                    try server.read()
                                    
                                    peripheral.database = server.database
                                    
                                    let _ = try server.write()
                                    
                                    if let writtenValues = didWriteValues {
                                        
                                        peripheral.didWrite?(writtenValues)
                                    }
                                }
                                
                                catch {
                                    
                                    do { try peripheral.controller.enableLowEnergyAdvertising() }
                                    catch HCIError.commandDisallowed { /* ignore */ }
                                    catch { fatalError("Could not enable advertising.") }
                                    
                                    peripheral.log?("Central \(newSocket.address) disconnected")
                                    
                                    return
                                }
                            }
                        })
                        
                        newConnectionThread.start()
                    }
                        
                    catch { peripheral.log?("Error waiting for new connection: \(error)") }
                }
                
                peripheral.log?("Stopped GATT Server")
                })
            
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
        
        // MARK: Subscript
        
        public subscript(characteristic handle: UInt16) -> Data {
            
            get { return database[handle: handle].value }
            
            set { database.write(newValue, forAttribute: handle) }
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
            /*
            let central: Central
            
            let server: GATTServer
            
            let thread: Thread
            
            private(set) weak var peripheral: LinuxPeripheral!
            
            init(socket: L2CAPSocket, peripheral: LinuxPeripheral) {
                
                self.central = Central(socket: socket)
                
                self.server = GATTServer(socket: socket)
                server.database = peripheral.database
                
               
            }*/
        }
    }

#endif

#if os(Linux)

    /// The platform specific peripheral.
    public typealias PeripheralManager = LinuxPeripheral

#endif
