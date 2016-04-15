//
//  LinuxPeripheral.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/2/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import SwiftFoundation
import Bluetooth
import BluetoothLinux

#if os(Linux)
    /// The platform specific peripheral.
    public typealias PeripheralManager = LinuxPeripheral
#endif

public final class LinuxPeripheral: NativePeripheral {
    
    // MARK: - Properties
    
    public var log: (String -> ())?
    
    public let maximumTransmissionUnit: Int
    
    public let adapter: Adapter
    
    public var willRead: ((central: Central, UUID: Bluetooth.UUID, value: Data, offset: Int) -> ATT.Error?)?
    
    public var willWrite: ((central: Central, UUID: Bluetooth.UUID, value: Data, newValue: (newValue: Data, newBytes: Data, offset: Int)) -> ATT.Error?)?
    
    // MARK: - Private Properties
    
    private var database = Atomic(GATTDatabase())
    
    private var isServerRunning = Atomic(false)
    
    private var serverSocket: L2CAPSocket!
    
    private var serverThread: Thread!
    
    // MARK: - Initialization
    
    public init(adapter: Adapter = try! Adapter(), maximumTransmissionUnit: Int = ATT.MTU.LowEnergy.Default) {
        
        self.adapter = adapter
        self.maximumTransmissionUnit = maximumTransmissionUnit
    }
    
    // MARK: - Methods
    
    public func start() throws {
        
        guard isServerRunning.value == false else { return }
        
        let adapterAddress = try Address(deviceIdentifier: adapter.identifier)
        
        let serverSocket = try L2CAPSocket(adapterAddress: adapterAddress, channelIdentifier: ATT.CID, addressType: .LowEnergyPublic, securityLevel: .Low)
        
        isServerRunning.value = true
        
        log?("Started GATT Server")
        
        let serverThread = try! Thread({ [weak self] in
            
            guard let peripheral = self else { return }
            
            while peripheral.isServerRunning.value {
                
                do {
                    
                    let newSocket = try serverSocket.waitForConnection()
                    
                    peripheral.log?("New \(newSocket.addressType) connection from \(newSocket.address)")
                    
                    let server = GATTServer(socket: newSocket)
                    
                    server.log = { peripheral.log?("[\(newSocket.address)]: " + $0) }
                    
                    server.willRead = { peripheral.willRead?(central: Central(socket: newSocket), UUID: $0.UUID, value: $0.value, offset: $0.offset) }
                    
                    server.database = peripheral.database.value
                    
                    // create new thread for new connection
                    
                    let _ = try! Thread({
                        
                        while peripheral.isServerRunning.value {
                            
                            do {
                                
                                var pendingWrite = true
                                
                                while pendingWrite {
                                    
                                    pendingWrite = try server.write()
                                }
                                
                                guard peripheral.isServerRunning.value else { return }
                                
                                server.database = peripheral.database.value
                                
                                try server.read()
                                
                                peripheral.database.value = server.database
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
        
        guard isServerRunning.value else { return }
        
        isServerRunning.value = false
        
        self.serverSocket = nil
        self.serverThread = nil
    }
    
    public func add(service: Service) throws -> Int {
        
        return database.value.add(service)
    }
    
    public func remove(service index: Int) {
        
        database.value.remove(service: index)
    }
    
    public func clear() {
        
        database.value.clear()
    }
    
    // MARK: Subscript
    
    public subscript(characteristic UUID: Bluetooth.UUID) -> Data {
        
        get { return database.value.attributes.filter({ $0.UUID == UUID}).first!.value }
        
        set {
            
            let matchingAttributes = database.value.attributes.filter({ $0.UUID == UUID })
            
            assert(matchingAttributes.count == 1, "\(matchingAttributes.count) Attributes with UUID \(UUID)")
            
            database.value.write(newValue, forAttribute: matchingAttributes[0].handle)
        }
    }
}