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
        
        public let preferredMaximumTransmissionUnit: ATTMaximumTransmissionUnit
        
        public let controller: HostController
        
        public var willRead: ((_ central: Central, _ uuid: BluetoothUUID, _ handle: UInt16, _ value: Data, _ offset: Int) -> ATT.Error?)?
        
        public var willWrite: ((_ central: Central, _ uuid: BluetoothUUID, _ handle: UInt16, _ value: Data, _ newValue: Data) -> ATT.Error?)?
        
        public var didWrite: ((_ central: Central, _ uuid: BluetoothUUID, _ handle: UInt16, _ value: Data, _ newValue: Data) -> ())?
        
        // MARK: - Private Properties
        
        private var database = GATTDatabase()
        
        private var isServerRunning = false
        
        private var serverSocket: L2CAPSocket!
        
        private var serverThread: Thread!
        
        // MARK: - Initialization
        
        public init(controller: HostController,
                    preferredMaximumTransmissionUnit: ATTMaximumTransmissionUnit = .default) {
            
            self.controller = controller
            self.preferredMaximumTransmissionUnit = preferredMaximumTransmissionUnit
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
                                
                                do {
                                    
                                    var didWriteValues: (central: Central, uuid: BluetoothUUID, handle: UInt16, value: Data, newValue: Data)?
                                    
                                    server.willRead = { (uuid, handle, value, offset)  in
                                        peripheral.willRead?(Central(socket: newSocket), uuid, handle, value, offset)
                                    }
                                    
                                    server.willWrite = { (uuid, handle, value, newValue) in
                                        
                                        if let error = peripheral.willWrite?(Central(socket: newSocket), uuid, handle, value, newValue) {
                                            
                                            return error
                                        }
                                        
                                        didWriteValues = (central: Central(socket: newSocket), uuid: uuid, handle: handle, value: value, newValue: newValue)
                                        
                                        return nil
                                    }
                                    
                                    server.database = peripheral.database
                                    
                                    try server.read()
                                    
                                    peripheral.database = server.database
                                    
                                    let _ = try server.write()
                                    
                                    if let writtenValues = didWriteValues {
                                        
                                        peripheral.didWrite?(writtenValues.central, writtenValues.uuid, writtenValues.handle, writtenValues.value, writtenValues.newValue)
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
            self.serverThread.start()
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

#endif

#if os(Linux)

    /// The platform specific peripheral.
    public typealias PeripheralManager = LinuxPeripheral

#endif
