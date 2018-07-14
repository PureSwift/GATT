//
//  TestCentral.swift
//  GATTTests
//
//  Created by Alsey Coleman Miller on 7/13/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import Bluetooth
@testable import GATT

final class TestCentral: CentralProtocol {
    
    var log: ((String) -> ())?
    
    let socket: TestL2CAPSocket
    
    let maximumTransmissionUnit: ATTMaximumTransmissionUnit
    
    lazy var client: GATTClient = GATTClient(socket: self.socket,
                                             maximumTransmissionUnit: self.maximumTransmissionUnit,
                                             log: { self.log?($0) })
    
    let peripheral: TestPeripheral
    
    var foundDevices = [ScanData]()
    
    var connectedDevice: Peripheral?
    
    internal private(set) var foundPeripherals = [Peripheral]()
    
    internal private(set) var foundServices = [GATTClient.Service]()
    
    internal private(set) var foundCharacteristics = [BluetoothUUID: [GATTClient.Characteristic]]()
    
    init(socket: TestL2CAPSocket,
         peripheral: TestPeripheral,
         maximumTransmissionUnit: ATTMaximumTransmissionUnit = .default,
         log: ((String) -> ())? = nil) {
        
        self.socket = socket
        self.maximumTransmissionUnit = maximumTransmissionUnit
        self.log = log
        self.peripheral = peripheral
    }
    
    func scan(filterDuplicates: Bool = true,
              shouldContinueScanning: () -> (Bool),
              foundDevice: @escaping (ScanData) -> ()) throws {
        
        foundDevices.forEach { foundDevice($0) }
        
        foundPeripherals = foundDevices.map { $0.peripheral }
    }
    
    func connect(to peripheral: Peripheral, timeout: TimeInterval = 30) throws {
        
        guard foundPeripherals.contains(peripheral)
            else { throw CentralError.unknownPeripheral(peripheral) }
        
        connectedDevice = peripheral
        
        // exchange mtu
        try run()
    }
    
    func discoverServices(_ services: [BluetoothUUID] = [],
                          for peripheral: Peripheral,
                          timeout: TimeInterval = 30) throws -> [Service] {
        
        guard foundPeripherals.contains(peripheral)
            else { throw CentralError.unknownPeripheral(peripheral) }
        
        guard connectedDevice == peripheral
            else { throw CentralError.disconnected(peripheral) }
        
        var response: GATTClientResponse<[GATTClient.Service]>!
        
        client.discoverAllPrimaryServices { response = $0 }
        
        while response == nil { try run() }
        
        switch response! {
            
        case let .error(error):
            
            throw error
            
        case let .value(value):
            
            self.foundServices = value
            
            return value.map { Service(uuid: $0.uuid, isPrimary: $0.type == .primaryService) }
        }
    }
    
    func discoverCharacteristics(_ characteristics: [BluetoothUUID] = [],
                                 for service: BluetoothUUID,
                                 peripheral: Peripheral,
                                 timeout: TimeInterval = 30) throws -> [Characteristic] {
        
        guard foundPeripherals.contains(peripheral)
            else { throw CentralError.unknownPeripheral(peripheral) }
        
        guard connectedDevice == peripheral
            else { throw CentralError.disconnected(peripheral) }
        
        guard let gattService = self.foundServices.first(where: { $0.uuid == service })
            else { throw CentralError.invalidAttribute(service) }
        
        var response: GATTClientResponse<[GATTClient.Characteristic]>!
        
        client.discoverAllCharacteristics(of: gattService) { response = $0 }
        
        while response == nil { try run() }
        
        switch response! {
            
        case let .error(error):
            
            throw error
            
        case let .value(value):
            
            self.foundCharacteristics[service] = value
            
            return value.map { Characteristic(uuid: $0.uuid, properties: $0.properties) }
        }
    }
    
    func readValue(for characteristic: BluetoothUUID,
                   service: BluetoothUUID,
                   peripheral: Peripheral,
                   timeout: TimeInterval = 30) throws -> Data {
        
        guard foundPeripherals.contains(peripheral)
            else { throw CentralError.unknownPeripheral(peripheral) }
        
        guard connectedDevice == peripheral
            else { throw CentralError.disconnected(peripheral) }
        
        guard let gattService = self.foundCharacteristics[service]
            else { throw CentralError.invalidAttribute(service) }
        
        guard let gattCharacteristic = gattService.first(where: { $0.uuid == characteristic })
            else { throw CentralError.invalidAttribute(characteristic) }
        
        var response: GATTClientResponse<Data>!
        
        client.readCharacteristic(gattCharacteristic) { response = $0 }
        
        while response == nil { try run() }
        
        switch response! {
            
        case let .error(error):
            
            throw error
            
        case let .value(value):
            
            return value
        }
    }
    
    func writeValue(_ data: Data,
                    for characteristic: BluetoothUUID,
                    withResponse: Bool = true,
                    service: BluetoothUUID,
                    peripheral: Peripheral,
                    timeout: TimeInterval = 30) throws {
        
        guard foundPeripherals.contains(peripheral)
            else { throw CentralError.unknownPeripheral(peripheral) }
        
        guard connectedDevice == peripheral
            else { throw CentralError.disconnected(peripheral) }
        
        guard foundPeripherals.contains(peripheral)
            else { throw CentralError.unknownPeripheral(peripheral) }
        
        guard connectedDevice == peripheral
            else { throw CentralError.disconnected(peripheral) }
        
        guard let gattService = self.foundCharacteristics[service]
            else { throw CentralError.invalidAttribute(service) }
        
        guard let gattCharacteristic = gattService.first(where: { $0.uuid == characteristic })
            else { throw CentralError.invalidAttribute(characteristic) }
        
        var response: GATTClientResponse<()>!
        
        client.writeCharacteristic(gattCharacteristic, data: data) { response = $0 }
        
        while response == nil { try run() }
        
        switch response! {
            
        case let .error(error):
            
            throw error
            
        case .value:
            
            return
        }
    }
    
    func notify(_ notification: ((Data) -> ())?,
                for characteristic: BluetoothUUID,
                service: BluetoothUUID,
                peripheral: Peripheral,
                timeout: TimeInterval = 30) throws {
        
        guard foundPeripherals.contains(peripheral)
            else { throw CentralError.unknownPeripheral(peripheral) }
        
        guard connectedDevice == peripheral
            else { throw CentralError.disconnected(peripheral) }
        
        
    }
    
    func disconnect(peripheral: Peripheral) {
        
        connectedDevice = nil
    }
    
    func disconnectAll() {
        
        connectedDevice = nil
    }
    
    private func run() throws {
        
        let server = (gatt: self.peripheral.client.server, socket: self.peripheral.socket)
        let client = (gatt: self.client, socket: self.socket)
        
        var didWrite = false
        repeat {
            
            didWrite = false
            
            while try client.gatt.write() {
                
                didWrite = true
            }
            
            while server.socket.receivedData.isEmpty == false {
                
                try server.gatt.read()
            }
            
            while try server.gatt.write() {
                
                didWrite = true
            }
            
            while client.socket.receivedData.isEmpty == false {
                
                try client.gatt.read()
            }
            
        } while didWrite
    }
}
