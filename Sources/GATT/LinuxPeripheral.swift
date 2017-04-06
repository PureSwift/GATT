//
//  LinuxPeripheral.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/2/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

#if os(Linux) || XcodeLinux
    
    import class Foundation.Thread
    import struct Foundation.Data
    import Bluetooth
    import BluetoothLinux
    
    public final class LinuxPeripheral: NativePeripheral {
        
        // MARK: - Properties
        
        public var log: ((String) -> ())?
        
        public let maximumTransmissionUnit: Int
        
        public let adapter: Adapter
        
        public var willRead: ((_ central: Central, _ UUID: BluetoothUUID, _ value: Data, _ offset: Int) -> ATT.Error?)?
        
        public var willWrite: ((_ central: Central, _ UUID: BluetoothUUID, _ value: Data, _ newValue: Data) -> ATT.Error?)?
        
        public var didWrite: ((_ central: Central, _ UUID: BluetoothUUID, _ value: Data, _ newValue: Data) -> ())?
        
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
        
        public func start(beacon: Beacon? = nil) throws {
            
            guard isServerRunning == false else { return }
            
            if let beacon = beacon {
                
                try adapter.enableBeacon(UUID: beacon.UUID, major: beacon.major, minor: beacon.minor, RSSI: beacon.RSSI, interval: beacon.interval)
                
            } else {
                
                do { try adapter.enableAdvertising() }
                catch HCIError.CommandDisallowed { /* ignore */ }
            }
            
            let adapterAddress = try Address(deviceIdentifier: adapter.identifier)
            
            let serverSocket = try L2CAPSocket(adapterAddress: adapterAddress, channelIdentifier: ATT.CID, addressType: .LowEnergyPublic, securityLevel: .Low)
            
            isServerRunning = true
            
            log?("Started GATT Server")
            
            let serverThread = try! Thread(block: { [weak self] in
                
                guard let peripheral = self else { return }
                
                while peripheral.isServerRunning {
                    
                    do {
                        
                        let newSocket = try serverSocket.waitForConnection()
                        
                        peripheral.log?("New \(newSocket.addressType) connection from \(newSocket.address)")
                        
                        let server = GATTServer(socket: newSocket)
                        
                        server.log = { peripheral.log?("[\(newSocket.address)]: " + $0) }
                        
                        server.database = peripheral.database
                        
                        // create new thread for new connection
                        
                        let _ = Thread(block: {
                            
                            while peripheral.isServerRunning {
                                
                                do {
                                    
                                    var didWriteValues: (central: Central, UUID: BluetoothUUID, value: Data, newValue: Data)?
                                    
                                    server.willRead = { peripheral.willRead?(Central(socket: newSocket), $0.0, $0.1, $0.2) }
                                    
                                    server.willWrite = { (write) in
                                        
                                        if let error = peripheral.willWrite?(Central(socket: newSocket), write.0, write.1, write.2) {
                                            
                                            return error
                                        }
                                        
                                        didWriteValues = (central: Central(socket: newSocket), UUID: write.0, value: write.1, newValue: write.2)
                                        
                                        return nil
                                    }
                                    
                                    server.database = peripheral.database
                                    
                                    try server.read()
                                    
                                    peripheral.database = server.database
                                    
                                    let _ = try server.write()
                                    
                                    if let writtenValues = didWriteValues {
                                        
                                        peripheral.didWrite?(writtenValues.central, writtenValues.UUID, writtenValues.value, writtenValues.newValue)
                                    }
                                }
                                    
                                catch {
                                    
                                    /// Turn on LE advertising after disconnect (Linux turns if off for some reason)
                                    if let disconnectError = error as? POSIXError,
                                    disconnectError.code.rawValue == 104
                                    || disconnectError.code.rawValue == 110 {
                                        
                                        peripheral.log?("Central \(newSocket.address) disconnected")
                                        
                                        do { try peripheral.adapter.enableAdvertising() }
                                        
                                        catch { peripheral.log?("Could not restore advertising. \(error)") }
                                        
                                        return
                                    }
                                    
                                    peripheral.log?("Error: \(error)"); return
                                }
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
        
        public subscript(characteristic UUID: BluetoothUUID) -> Data {
            
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
