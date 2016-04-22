//
//  LinuxPeripheral.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/2/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

#if os(Linux) || XcodeLinux
    
    import SwiftFoundation
    import Bluetooth
    import BluetoothLinux
    
    public final class LinuxPeripheral: NativePeripheral {
        
        // MARK: - Properties
        
        public var log: (String -> ())?
        
        public let maximumTransmissionUnit: Int
        
        public let adapter: Adapter
        
        public var willRead: ((central: Central, UUID: Bluetooth.UUID, value: Data, offset: Int) -> ATT.Error?)?
        
        public var willWrite: ((central: Central, UUID: Bluetooth.UUID, value: Data, newValue: Data) -> ATT.Error?)?
        
        public var didWrite: ((central: Central, UUID: Bluetooth.UUID, value: Data, newValue: Data) -> ())?
        
        // MARK: - Private Properties
        
        private var database = GATTDatabase()
        
        private var isServerRunning = false
        
        private var serverSocket: L2CAPSocket!
        
        private var serverThread: Thread!
        
        // MARK: - Initialization
        
        public init(adapter: Adapter = try! Adapter(), maximumTransmissionUnit: Int = ATT.MTU.LowEnergy.Default) {
            
            self.adapter = adapter
            self.maximumTransmissionUnit = maximumTransmissionUnit
        }
        
        // MARK: - Methods
        
        public func start() throws {
            
            guard isServerRunning == false else { return }
            
            let adapterAddress = try Address(deviceIdentifier: adapter.identifier)
            
            let serverSocket = try L2CAPSocket(adapterAddress: adapterAddress, channelIdentifier: ATT.CID, addressType: .LowEnergyPublic, securityLevel: .Low)
            
            isServerRunning = true
            
            log?("Started GATT Server")
            
            let serverThread = try! Thread({ [weak self] in
                
                guard let peripheral = self else { return }
                
                while peripheral.isServerRunning {
                    
                    do {
                        
                        let newSocket = try serverSocket.waitForConnection()
                        
                        peripheral.log?("New \(newSocket.addressType) connection from \(newSocket.address)")
                        
                        let server = GATTServer(socket: newSocket)
                        
                        server.log = { peripheral.log?("[\(newSocket.address)]: " + $0) }
                        
                        server.database = peripheral.database
                        
                        // create new thread for new connection
                        
                        let _ = try! Thread({
                            
                            while peripheral.isServerRunning {
                                
                                do {
                                    
                                    var didWrite: (central: Central, UUID: Bluetooth.UUID, value: Data, newValue: Data)?
                                    
                                    server.willRead = { peripheral.willRead?(central: Central(socket: newSocket), UUID: $0.UUID, value: $0.value, offset: $0.offset) }
                                    
                                    server.willWrite = { (write) in
                                        
                                        if let error = peripheral.willWrite?(central: Central(socket: newSocket), UUID: write.UUID, value: write.value, newValue: write.newValue) {
                                            
                                            return error
                                        }
                                        
                                        didWrite = (central: Central(socket: newSocket), UUID: write.UUID, value: write.value, newValue: write.newValue)
                                        
                                        return nil
                                    }

                                    server.database = peripheral.database

                                    try server.read()
                                    
                                    peripheral.database = server.database
                                    
                                    try server.write()
                                    
                                    if let didWrite = didWrite {
                                        
                                        peripheral.didWrite?(central: didWrite.central, UUID: didWrite.UUID, value: didWrite.value, newValue: didWrite.newValue)
                                    }
                                }
                                    
                                catch { peripheral.log?("Error: \(error)"); return }
                            }
                        })
                    }
                        
                    catch { peripheral.log?("Error waiting for new connection: \(error)") }
                }
                
                peripheral.log?("Stopped GATT Server")
                })
            
            self.serverSocket = serverSocket
            self.serverThread = serverThread
        }
        
        public func stop() {
            
            guard isServerRunning else { return }
            
            isServerRunning = false
            
            self.serverSocket = nil
            self.serverThread = nil
        }
        
        public func add(service: Service) throws -> UInt16 {
            
            return database.add(service: service)
        }
        
        public func remove(service handle: UInt16) {
            
            database.remove(service: handle)
        }
        
        public func clear() {
            
            database.clear()
        }
        
        // MARK: Subscript
        
        public subscript(characteristic UUID: Bluetooth.UUID) -> Data {
            
            get { return database.attributes.filter({ $0.UUID == UUID}).first!.value }
            
            set {
                
                let matchingAttributes = database.attributes.filter({ $0.UUID == UUID })
                
                assert(matchingAttributes.count == 1, "\(matchingAttributes.count) Attributes with UUID \(UUID)")
                
                let attribute = matchingAttributes.first!
                
                database.write(newValue, forAttribute: attribute.handle)
                
                //assert(self[characteristic: UUID] == newValue, "New Characteristic value \(UUID) could not be written.")
            }
        }
    }

#endif

#if os(Linux)

    /// The platform specific peripheral.
    public typealias PeripheralManager = LinuxPeripheral

#endif
