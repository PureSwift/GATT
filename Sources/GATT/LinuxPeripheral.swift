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
        
        isServerRunning = false
        
        let adapterAddress = try Address(deviceIdentifier: adapter.identifier)
        
        let serverSocket = try L2CAPSocket(adapterAddress: adapterAddress, channelIdentifier: ATT.CID, addressType: .LowEnergyPublic, securityLevel: .Low)
        
        let serverThread = try Thread(closure: { [weak self] in
            
            guard let peripheral = self else { return }
            
            do {
                
                let newSocket = try serverSocket.waitForConnection()
                
                peripheral.log?("New \(newSocket.addressType) connection from \(newSocket.address)")
                
                let server = GATTServer(socket: newSocket)
                
                server.log = { peripheral.log?("[\(newSocket.address)]: " + $0) }
                
                server.database = peripheral.database
                
                // create new thread for new connection
                
                let connectionThread = try Thread(closure: {
                    
                    
                })
            }
            
            catch { peripheral.log?("Error: \(error)") }
        })
        
        self.serverSocket = serverSocket
        self.serverThread = serverThread
        
        isServerRunning = true
    }
    
    public func stop() {
        
        guard isServerRunning else { return }
        
        self.serverSocket = nil
        self.serverThread = nil
    }
    
    public func add(service: Service) throws -> Int {
        
        return database.add(service)
    }
    
    public func remove(service index: Int) {
        
        database.remove(service: index)
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
            
            database.write(newValue, forAttribute: matchingAttributes[0].handle)
        }
    }
}