//
//  TestPeripheral.swift
//  GATTTests
//
//  Created by Alsey Coleman Miller on 7/13/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import Bluetooth
import XCTest
@testable import GATT

final class TestPeripheral: PeripheralProtocol {
    
    // MARK: - Properties
    
    var log: ((String) -> ())?
    
    let options: Options
    
    var willRead: ((GATTReadRequest) -> ATT.Error?)?
    
    var willWrite: ((GATTWriteRequest) -> ATT.Error?)?
    
    var didWrite: ((GATTWriteConfirmation) -> ())?
    
    // MARK: - Private Properties
    
    internal let socket: TestL2CAPSocket
    
    internal var database: GATTDatabase {
        
        get { return client.server.database }
        
        set { client.server.database = newValue }
    }
    
    internal private(set) var isServerRunning = false
    
    internal private(set) lazy var client: Client = Client(socket: self.socket, peripheral: self)
    
    internal private(set) var lastConnectionID = 0
    
    // MARK: - Initialization
    
    init(socket: TestL2CAPSocket,
         options: Options = Options()) {
        
        self.socket = socket
        self.options = options
    }
    
    deinit {
        
        stop()
    }
    
    // MARK: - Methods
    
    func start() throws {
        
        guard isServerRunning == false else { return }
        
        // enable advertising
        //do { try controller.enableLowEnergyAdvertising() }
        //catch HCIError.commandDisallowed { /* ignore */ }
        
        isServerRunning = true
        
        log?("Started GATT Server")
    }
    
    func stop() {
        
        guard isServerRunning else { return }
        
        isServerRunning = false
        
        log?("Stopped GATT Server")
    }
    
    func add(service: GATT.Service) throws -> UInt16 {
        
        return database.add(service: service)
    }
    
    func remove(service handle: UInt16) {
        
        database.remove(service: handle)
    }
    
    func removeAllServices() {
        
        database.removeAll()
    }
    
    /// Return the handles of the characteristics matching the specified UUID.
    func characteristics(for uuid: BluetoothUUID) -> [UInt16] {
        
        return database.filter { $0.uuid == uuid }.map { $0.handle }
    }
    
    fileprivate func newConnectionID() -> Int {
        
        lastConnectionID += 1
        
        return lastConnectionID
    }
    
    // MARK: Subscript
    
    subscript(characteristic handle: UInt16) -> Data {
        
        get { return database[handle: handle].value }
        
        set { client.server.writeValue(newValue, forCharacteristic: handle) }
    }
}

extension TestPeripheral {
    
    struct Options {
        
        let maximumTransmissionUnit: ATTMaximumTransmissionUnit
        
        let maximumPreparedWrites: Int
        
        init(maximumTransmissionUnit: ATTMaximumTransmissionUnit = .default,
                    maximumPreparedWrites: Int = 100) {
            
            self.maximumTransmissionUnit = maximumTransmissionUnit
            self.maximumPreparedWrites = maximumPreparedWrites
        }
    }
}

internal extension TestPeripheral {
    
    final class Client {
        
        let connectionID: Int
        
        let central: Central
        
        let server: GATTServer
        
        private(set) weak var peripheral: TestPeripheral!
        
        private var maximumUpdateValueLength: Int {
            
            // ATT_MTU-3
            return Int(server.maximumTransmissionUnit.rawValue) - 3
        }
        
        init(socket: TestL2CAPSocket, peripheral: TestPeripheral) {
            
            // initialize
            self.peripheral = peripheral
            self.connectionID = peripheral.newConnectionID()
            self.central = Central(identifier: UUID())
            self.server = GATTServer(socket: socket,
                                     maximumTransmissionUnit: peripheral.options.maximumTransmissionUnit,
                                     maximumPreparedWrites: peripheral.options.maximumPreparedWrites)
            
            // start running
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
            
            
        }
    }
}
