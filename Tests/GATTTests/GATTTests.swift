//
//  GATTTests.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 7/12/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import XCTest
import Bluetooth
@testable import GATT

@available(OSX 10.12, *)
final class GATTTests: XCTestCase {
    
    static var allTests = [
        ("testMTUExchange", testMTUExchange),
        ("testServiceDiscovery", testServiceDiscovery),
        ("testCharacteristicValue", testCharacteristicValue),
        ("testNotification", testNotification),
        ("testAdvertisingData", testAdvertisingData)
        ]
    
    func testMTUExchange() {
        
        /**
         Exchange MTU Request - MTU:104
         Opcode: 0x02
         Client Rx MTU: 0x0068
         
         Exchange MTU Response - MTU:200
         Opcode: 0x03
         Client Rx MTU: 0x00c8
         */
        
        let clientMTU = ATTMaximumTransmissionUnit(rawValue: 104)! // 0x0068
        let serverMTU = ATTMaximumTransmissionUnit(rawValue: 200)! // 0x00c8
        let finalMTU = clientMTU
        XCTAssertEqual(ATTMaximumTransmissionUnit(server: clientMTU.rawValue, client: serverMTU.rawValue), finalMTU)
        
        let testPDUs: [(ATTProtocolDataUnit, [UInt8])] = [
            (ATTMaximumTransmissionUnitRequest(clientMTU: clientMTU.rawValue),
             [0x02, 0x68, 0x00]),
            (ATTMaximumTransmissionUnitResponse(serverMTU: serverMTU.rawValue),
             [0x03, 0xC8, 0x00])
        ]
        
        // decode and validate bytes
        test(testPDUs)
        
        // setup sockets
        let serverSocket = TestL2CAPSocket(name: "Server")
        let clientSocket = TestL2CAPSocket(name: "Client")
        clientSocket.target = serverSocket
        serverSocket.target = clientSocket
        
        // host controller
        let serverHostController = PeripheralHostController(address: .any)
        let clientHostController = CentralHostController(address: .any)
        
        // peripheral
        typealias TestPeripheral = GATTPeripheral<PeripheralHostController, TestL2CAPSocket>
        let options = GATTPeripheralOptions(maximumTransmissionUnit: serverMTU, maximumPreparedWrites: .max)
        let peripheral = TestPeripheral(controller: serverHostController, options: options)
        peripheral.log = { print("Peripheral:", $0) }
        
        var incomingConnections = [(serverSocket, Central(identifier: serverSocket.address))]
        
        peripheral.newConnection = {
            
            repeat {
                if let newConnecion = incomingConnections.popFirst() {
                    return newConnecion
                } else {
                    sleep(1)
                }
            } while true
        }
         
        XCTAssertNoThrow(try peripheral.start())
        defer { peripheral.stop() }
        
        // central
        typealias TestCentral = GATTCentral<CentralHostController, TestL2CAPSocket>
        let central = TestCentral(hostController: clientHostController, maximumTransmissionUnit: clientMTU)
        central.log = { print("Central:", $0) }
        central.newConnection = { (report) in
            return clientSocket
        }
        central.hostController.scanEvents = [
            /**
             Jul 26 15:32:14.813  HCI Event        0x0000  12:3B:6A:1B:36:A8  LE Meta Event - LE Advertising Report - 0 - 12:3B:6A:1B:36:A8  -86 dBm - abeacon_36A8
             Parameter Length: 26 (0x1A)
             Num Reports: 0X01
             Event Type: Scan Response (SCAN_RSP)
             Address Type: Public
             Peer Address: 12:3B:6A:1B:36:A8
             Length Data: 0X0E
             Local Name: abeacon_36A8
             Data: 0D 09 61 62 65 61 63 6F 6E 5F 33 36 41 38 
             RSSI: -86 dBm
            */
            Data([/* 0x3E, 0x1A, */ 0x02, 0x01, 0x04, 0x00, 0xA8, 0x36, 0x1B, 0x6A, 0x3B, 0x12, 0x0E, 0x0D, 0x09, 0x61, 0x62, 0x65, 0x61, 0x63, 0x6F, 0x6E, 0x5F, 0x33, 0x36, 0x41, 0x38, 0xAA])
        ]
        var foundDevices = [Peripheral]()
        XCTAssertNoThrow(foundDevices = try central.scan(duration: 0.001).map { $0.peripheral })
        
        guard let device = foundDevices.first
            else { XCTFail(); return }
        
        XCTAssertNoThrow(try central.connect(to: device))
        defer { central.disconnectAll() }
        
        sleep(1)
        
        XCTAssertEqual(peripheral.connections.values.first?.maximumUpdateValueLength, Int(finalMTU.rawValue) - 3)
        XCTAssertEqual(central.connections.values.first?.maximumUpdateValueLength, Int(finalMTU.rawValue) - 3)
        
        // validate GATT PDUs
        let mockData = split(pdu: testPDUs.map { $0.1 })
        
        XCTAssertEqual(serverSocket.cache, mockData.server)
        XCTAssertEqual(clientSocket.cache, mockData.client)
    }
    
    func testServiceDiscovery() {
        
        let clientMTU = ATTMaximumTransmissionUnit(rawValue: 104)! // 0x0068
        let serverMTU = ATTMaximumTransmissionUnit.default // 23
        let finalMTU = serverMTU
        XCTAssertEqual(ATTMaximumTransmissionUnit(server: clientMTU.rawValue, client: serverMTU.rawValue), finalMTU)
        
        let testPDUs: [(ATTProtocolDataUnit, [UInt8])] = [
            /**
             Exchange MTU Request - MTU:104
             Opcode: 0x02
             Client Rx MTU: 0x0068
             */
            (ATTMaximumTransmissionUnitRequest(clientMTU: clientMTU.rawValue),
             [0x02, 0x68, 0x00]),
            /**
             Exchange MTU Response - MTU:23
             Opcode: 0x03
             Client Rx MTU: 0x0017
             */
            (ATTMaximumTransmissionUnitResponse(serverMTU: serverMTU.rawValue),
             [0x03, 0x17, 0x00]),
            /**
             Read By Group Type Request - Start Handle:0x0001 - End Handle:0xffff - UUID:2800 (GATT Primary Service Declaration)
             Opcode: 0x10
             Starting Handle: 0x0001
             Ending Handle: 0xffff
             Attribute Group Type: 2800 (GATT Primary Service Declaration)
             */
            (ATTReadByGroupTypeRequest(startHandle: 0x0001, endHandle: 0xffff, type: .primaryService),
            [0x10, 0x01, 0x00, 0xFF, 0xFF, 0x00, 0x28]),
            /**
             Read By Group Type Response
             Opcode: 0x11
             List Length: 0006
             Attribute Handle: 0x0001 End Group Handle: 0x0004 UUID: 180F (Battery Service)
             */
            (ATTReadByGroupTypeResponse(attributeData: [
                ATTReadByGroupTypeResponse.AttributeData(attributeHandle: 0x001,
                                                         endGroupHandle: 0x0004,
                                                         value: BluetoothUUID.batteryService.littleEndian.data)
                ])!,
            [0x11, 0x06, 0x01, 0x00, 0x04, 0x00, 0x0F, 0x18]),
            /**
             Read By Group Type Request - Start Handle:0x0005 - End Handle:0xffff - UUID:2800 (GATT Primary Service Declaration)
             Opcode: 0x10
             Starting Handle: 0x0005
             Ending Handle: 0xffff
             Attribute Group Type: 2800 (GATT Primary Service Declaration)
             */
            (ATTReadByGroupTypeRequest(startHandle: 0x0005, endHandle: 0xffff, type: .primaryService),
             [0x10, 0x05, 0x00, 0xFF, 0xFF, 0x00, 0x28]),
            /**
             Error Response - Attribute Handle: 0x0005 - Error Code: 0x0A - Attribute Not Found
             Opcode: 0x01
             Request Opcode In Error: 0x10 (Read By Group Type Request)
             Attribute Handle In Error: 0x0005 (5)
             Error Code: 0x0a (Attribute Not Found)
             */
            (ATTErrorResponse(request: .readByGroupTypeRequest, attributeHandle: 0x0005, error: .attributeNotFound),
             [0x01, 0x10, 0x05, 0x00, 0x0A])
        ]
        
        // decode and validate bytes
        test(testPDUs)
        
        // setup sockets
        let serverSocket = TestL2CAPSocket(name: "Server")
        let clientSocket = TestL2CAPSocket(name: "Client")
        clientSocket.target = serverSocket
        serverSocket.target = clientSocket
        
        // host controller
        let serverHostController = PeripheralHostController(address: .any)
        let clientHostController = CentralHostController(address: .any)
        
        // peripheral
        typealias TestPeripheral = GATTPeripheral<PeripheralHostController, TestL2CAPSocket>
        let options = GATTPeripheralOptions(maximumTransmissionUnit: serverMTU, maximumPreparedWrites: .max)
        let peripheral = TestPeripheral(controller: serverHostController, options: options)
        peripheral.log = { print("Peripheral:", $0) }
        
        var incomingConnections = [(serverSocket, Central(identifier: serverSocket.address))]
        
        peripheral.newConnection = {
            
            repeat {
                if let newConnecion = incomingConnections.popFirst() {
                    return newConnecion
                } else {
                    sleep(1)
                }
            } while true
        }
        
        // service
        let batteryLevel = GATTBatteryLevel(level: .min)
        
        let characteristics = [
            GATT.Characteristic(uuid: type(of: batteryLevel).uuid,
                                value: batteryLevel.data,
                                permissions: [.read],
                                properties: [.read, .notify],
                                descriptors: [GATTClientCharacteristicConfiguration().descriptor])
        ]
        
        let service = GATT.Service(uuid: .batteryService,
                                   primary: true,
                                   characteristics: characteristics)
        
        let serviceAttribute = try! peripheral.add(service: service)
        defer { peripheral.remove(service: serviceAttribute) }
        
        // start server
        XCTAssertNoThrow(try peripheral.start())
        defer { peripheral.stop() }
        
        // central
        typealias TestCentral = GATTCentral<CentralHostController, TestL2CAPSocket>
        let central = TestCentral(hostController: clientHostController, maximumTransmissionUnit: clientMTU)
        central.log = { print("Central:", $0) }
        central.newConnection = { (report) in
            return clientSocket
        }
        central.hostController.scanEvents = [
            /**
             Jul 26 15:32:14.813  HCI Event        0x0000  12:3B:6A:1B:36:A8  LE Meta Event - LE Advertising Report - 0 - 12:3B:6A:1B:36:A8  -86 dBm - abeacon_36A8
             Parameter Length: 26 (0x1A)
             Num Reports: 0X01
             Event Type: Scan Response (SCAN_RSP)
             Address Type: Public
             Peer Address: 12:3B:6A:1B:36:A8
             Length Data: 0X0E
             Local Name: abeacon_36A8
             Data: 0D 09 61 62 65 61 63 6F 6E 5F 33 36 41 38
             RSSI: -86 dBm
             */
            Data([/* 0x3E, 0x1A, */ 0x02, 0x01, 0x04, 0x00, 0xA8, 0x36, 0x1B, 0x6A, 0x3B, 0x12, 0x0E, 0x0D, 0x09, 0x61, 0x62, 0x65, 0x61, 0x63, 0x6F, 0x6E, 0x5F, 0x33, 0x36, 0x41, 0x38, 0xAA])
        ]
        
        // scan for devices
        var foundDevices = [Peripheral]()
        XCTAssertNoThrow(foundDevices = try central.scan(duration: 0.001).map { $0.peripheral })
        
        guard let device = foundDevices.first
            else { XCTFail("No peripherals scanned"); return }
        
        XCTAssertNoThrow(try central.connect(to: device))
        defer { central.disconnect(peripheral: device) }
        
        var services = [Service<Peripheral>]()
        XCTAssertNoThrow(services = try central.discoverServices(for: device))
        
        guard let foundService = services.first,
            services.count == 1
            else { XCTFail(); return }
        
        XCTAssertEqual(foundService.uuid, .batteryService)
        XCTAssertEqual(foundService.isPrimary, true)
        
        XCTAssertEqual(peripheral.connections.values.first?.maximumUpdateValueLength, Int(finalMTU.rawValue) - 3)
        XCTAssertEqual(central.connections.values.first?.maximumUpdateValueLength, Int(finalMTU.rawValue) - 3)
        
        // validate GATT PDUs
        let mockData = split(pdu: testPDUs.map { $0.1 })
        
        XCTAssertEqual(serverSocket.cache, mockData.server)
        XCTAssertEqual(clientSocket.cache, mockData.client)
    }
    
    
    func testCharacteristicValue() {
        
        // setup sockets
        let serverSocket = TestL2CAPSocket(name: "Server")
        let clientSocket = TestL2CAPSocket(name: "Client")
        clientSocket.target = serverSocket
        serverSocket.target = clientSocket
        
        // host controller
        let serverHostController = PeripheralHostController(address: .any)
        let clientHostController = CentralHostController(address: .any)
        
        // peripheral
        typealias TestPeripheral = GATTPeripheral<PeripheralHostController, TestL2CAPSocket>
        let options = GATTPeripheralOptions(maximumTransmissionUnit: .default, maximumPreparedWrites: .max)
        let peripheral = TestPeripheral(controller: serverHostController, options: options)
        peripheral.log = { print("Peripheral:", $0) }
        
        var incomingConnections = [(serverSocket, Central(identifier: serverSocket.address))]
        
        peripheral.newConnection = {
            
            repeat {
                if let newConnecion = incomingConnections.popFirst() {
                    return newConnecion
                } else {
                    sleep(1)
                }
            } while true
        }
        
        // service
        let batteryLevel = GATTBatteryLevel(level: .max)
        
        let characteristics = [
            GATT.Characteristic(uuid: type(of: batteryLevel).uuid,
                                value: batteryLevel.data,
                                permissions: [.read, .write],
                                properties: [.read, .write],
                                descriptors: [])
        ]
        
        let service = GATT.Service(uuid: .batteryService,
                                   primary: true,
                                   characteristics: characteristics)
        
        let serviceAttribute = try! peripheral.add(service: service)
        defer { peripheral.remove(service: serviceAttribute) }
        
        let characteristicValueHandle = peripheral.characteristics(for: .batteryLevel)[0]
        
        // start server
        XCTAssertNoThrow(try peripheral.start())
        defer { peripheral.stop() }
        
        // central
        typealias TestCentral = GATTCentral<CentralHostController, TestL2CAPSocket>
        let central = TestCentral(hostController: clientHostController, maximumTransmissionUnit: .default)
        central.log = { print("Central:", $0) }
        central.newConnection = { (report) in
            return clientSocket
        }
        central.hostController.scanEvents = [
            Data([0x02, 0x01, 0x04, 0x00, 0xA8, 0x36, 0x1B, 0x6A, 0x3B, 0x12, 0x0E, 0x0D, 0x09, 0x61, 0x62, 0x65, 0x61, 0x63, 0x6F, 0x6E, 0x5F, 0x33, 0x36, 0x41, 0x38, 0xAA])
        ]
        
        // scan for devices
        var foundDevices = [Peripheral]()
        XCTAssertNoThrow(foundDevices = try central.scan(duration: 0.001).map { $0.peripheral })
        
        guard let device = foundDevices.first
            else { XCTFail("No peripherals scanned"); return }
        
        XCTAssertNoThrow(try central.connect(to: device))
        defer { central.disconnect(peripheral: device) }
        
        var services = [Service<Peripheral>]()
        XCTAssertNoThrow(services = try central.discoverServices(for: device))
        
        guard let foundService = services.first,
            services.count == 1
            else { XCTFail(); return }
        
        XCTAssertEqual(foundService.uuid, .batteryService)
        XCTAssertEqual(foundService.isPrimary, true)
        
        var foundCharacteristics = [Characteristic<Peripheral>]()
        XCTAssertNoThrow(foundCharacteristics = try central.discoverCharacteristics(for: foundService))
        
        guard let foundCharacteristic = foundCharacteristics.first,
            foundCharacteristics.count == 1
            else { XCTFail(); return }
        
        XCTAssertEqual(foundCharacteristic.uuid, .batteryLevel)
        XCTAssertEqual(foundCharacteristic.properties, [.read, .write])
        
        // read value
        var characteristicData = Data()
        XCTAssertNoThrow(characteristicData = try central.readValue(for: foundCharacteristic))
        
        guard let characteristicValue = GATTBatteryLevel(data: characteristicData)
            else { XCTFail(); return }
        
        XCTAssertEqual(characteristicValue, batteryLevel)
        
        // write value
        let newValue = GATTBatteryLevel(level: .min)
        
        let didWriteExpectation = expectation(description: "Did Write")
        
        peripheral.willWrite = {
            XCTAssertEqual($0.uuid, .batteryLevel)
            XCTAssertEqual($0.value, batteryLevel.data)
            XCTAssertEqual($0.newValue, newValue.data)
            didWriteExpectation.fulfill()
            return nil
        }
        
        let willWriteExpectation = expectation(description: "Will Write")
        
        peripheral.didWrite = {
            XCTAssertEqual($0.uuid, .batteryLevel)
            XCTAssertEqual($0.value, newValue.data)
            willWriteExpectation.fulfill()
        }
        
        XCTAssertNoThrow(try central.writeValue(newValue.data, for: foundCharacteristic, withResponse: true))
        
        waitForExpectations(timeout: 1.0, handler: nil)
        
        XCTAssertEqual(peripheral[characteristic: characteristicValueHandle], newValue.data)
        XCTAssertNotEqual(peripheral[characteristic: characteristicValueHandle], characteristicValue.data)
        
        
    }
    
    func testNotification() {
        
        // setup sockets
        let serverSocket = TestL2CAPSocket(name: "Server")
        let clientSocket = TestL2CAPSocket(name: "Client")
        clientSocket.target = serverSocket
        serverSocket.target = clientSocket
        
        // host controller
        let serverHostController = PeripheralHostController(address: .any)
        let clientHostController = CentralHostController(address: .any)
        
        // peripheral
        typealias TestPeripheral = GATTPeripheral<PeripheralHostController, TestL2CAPSocket>
        let options = GATTPeripheralOptions(maximumTransmissionUnit: .default, maximumPreparedWrites: .max)
        let peripheral = TestPeripheral(controller: serverHostController, options: options)
        peripheral.log = { print("Peripheral:", $0) }
        
        var incomingConnections = [(serverSocket, Central(identifier: serverSocket.address))]
        
        peripheral.newConnection = {
            
            repeat {
                if let newConnecion = incomingConnections.popFirst() {
                    return newConnecion
                } else {
                    sleep(1)
                }
            } while true
        }
        
        // service
        let batteryLevel = GATTBatteryLevel(level: .min)
        
        let characteristics = [
            GATT.Characteristic(uuid: type(of: batteryLevel).uuid,
                                value: batteryLevel.data,
                                permissions: [.read],
                                properties: [.read, .notify],
                                descriptors: [GATTClientCharacteristicConfiguration().descriptor])
        ]
        
        let service = GATT.Service(uuid: .batteryService,
                                   primary: true,
                                   characteristics: characteristics)
        
        let serviceAttribute = try! peripheral.add(service: service)
        defer { peripheral.remove(service: serviceAttribute) }
        
        let characteristicValueHandle = peripheral.characteristics(for: .batteryLevel)[0]
        
        // start server
        XCTAssertNoThrow(try peripheral.start())
        defer { peripheral.stop() }
        
        // central
        typealias TestCentral = GATTCentral<CentralHostController, TestL2CAPSocket>
        let central = TestCentral(hostController: clientHostController, maximumTransmissionUnit: .default)
        central.log = { print("Central:", $0) }
        central.newConnection = { (report) in
            return clientSocket
        }
        central.hostController.scanEvents = [
            Data([0x02, 0x01, 0x04, 0x00, 0xA8, 0x36, 0x1B, 0x6A, 0x3B, 0x12, 0x0E, 0x0D, 0x09, 0x61, 0x62, 0x65, 0x61, 0x63, 0x6F, 0x6E, 0x5F, 0x33, 0x36, 0x41, 0x38, 0xAA])
        ]
        
        // scan for devices
        var foundDevices = [Peripheral]()
        XCTAssertNoThrow(foundDevices = try central.scan(duration: 0.001).map { $0.peripheral })
        
        guard let device = foundDevices.first
            else { XCTFail("No peripherals scanned"); return }
        
        XCTAssertNoThrow(try central.connect(to: device))
        defer { central.disconnect(peripheral: device) }
        
        var services = [Service<Peripheral>]()
        XCTAssertNoThrow(services = try central.discoverServices(for: device))
        
        guard let foundService = services.first,
            services.count == 1
            else { XCTFail(); return }
        
        XCTAssertEqual(foundService.uuid, .batteryService)
        XCTAssertEqual(foundService.isPrimary, true)
        
        var foundCharacteristics = [Characteristic<Peripheral>]()
        XCTAssertNoThrow(foundCharacteristics = try central.discoverCharacteristics(for: foundService))
        
        guard let foundCharacteristic = foundCharacteristics.first,
            foundCharacteristics.count == 1
            else { XCTFail(); return }
        
        XCTAssertEqual(foundCharacteristic.uuid, .batteryLevel)
        XCTAssertEqual(foundCharacteristic.properties, [.read, .notify])
        
        let notificationExpectation = self.expectation(description: "Notification")
        
        var notificationValue: GATTBatteryLevel?
        XCTAssertNoThrow(try central.notify({
            notificationValue = GATTBatteryLevel(data: $0)
            notificationExpectation.fulfill()
        }, for: foundCharacteristic))
        
        let newValue = GATTBatteryLevel(level: .max)
        
        // write new value, emit notifications
        peripheral[characteristic: characteristicValueHandle] = newValue.data
        
        // wait
        waitForExpectations(timeout: 2.0, handler: nil)
        
        // validate notification
        XCTAssertEqual(peripheral[characteristic: characteristicValueHandle], newValue.data, "Value not updated on peripheral")
        XCTAssertEqual(notificationValue, newValue, "Notification not recieved")
        
        // stop notifications
        XCTAssertNoThrow(try central.notify(nil, for: foundCharacteristic))
    }
    
    func testAdvertisingData() {
        
        do {
            
            let scanEvents = [
                /**
                 12:3B:6A:1B:36:A8  LE Meta Event - LE Advertising Report - 0 - 12:3B:6A:1B:36:A8  -86 dBm - abeacon_36A8
                 Parameter Length: 26 (0x1A)
                 Num Reports: 0X01
                 Event Type: Scan Response (SCAN_RSP)
                 Address Type: Public
                 Peer Address: 12:3B:6A:1B:36:A8
                 Length Data: 0X0E
                 Local Name: abeacon_36A8
                 Data: 0D 09 61 62 65 61 63 6F 6E 5F 33 36 41 38
                 RSSI: -86 dBm
                 */
                Data([/* 0x3E, 0x1A, */ 0x02, 0x01, 0x04, 0x00, 0xA8, 0x36, 0x1B, 0x6A, 0x3B, 0x12, 0x0E, 0x0D, 0x09, 0x61, 0x62, 0x65, 0x61, 0x63, 0x6F, 0x6E, 0x5F, 0x33, 0x36, 0x41, 0x38, 0xAA])
            ]
            
            
            // central
            typealias TestCentral = GATTCentral<CentralHostController, TestL2CAPSocket>
            let central = TestCentral(hostController: CentralHostController(address: .any))
            central.log = { print("Central:", $0) }
            central.hostController.scanEvents = scanEvents
            
            // scan for devices
            var scanResults = [ScanData<Peripheral, AdvertisementData>]()
            XCTAssertNoThrow(scanResults = try central.scan(duration: 0.1))
            
            guard let scanData = scanResults.first
                else { XCTFail("No peripherals scanned"); return }
            
            XCTAssertEqual(scanData.rssi, -86)
            XCTAssertEqual(scanData.peripheral.identifier.rawValue, "12:3B:6A:1B:36:A8")
            XCTAssertEqual(scanData.advertisementData.localName, "abeacon_36A8")
            //XCTAssertEqual(scanData.advertisementData.serviceUUIDs, [.bit16(0xFEF5)])
        }
    }
}

@available(OSX 10.12, *)
extension GATTTests {
    
    func test(_ testPDUs: [(ATTProtocolDataUnit, [UInt8])]) {
        
        // decode and compare
        for (testPDU, testData) in testPDUs {
            
            guard let decodedPDU = type(of: testPDU).init(data: Data(testData))
                else { XCTFail("Could not decode \(type(of: testPDU))"); return }
            
            //dump(decodedPDU)
            
            XCTAssertEqual(decodedPDU.data, Data(testData))
            
            var decodedDump = ""
            dump(decodedPDU, to: &decodedDump)
            var testDump = ""
            dump(testPDU, to: &testDump)
            
            // FIXME: Compare with Equatable
            // Data has different pointers, so dumps will always be different
            //XCTAssertEqual(decodedDump, testDump)
        }
    }
    
    func split(pdu data: [[UInt8]]) -> (server: [Data], client: [Data]) {
        
        var serverSocketData = [Data]()
        var clientSocketData = [Data]()
        
        for pduData in data {
            
            guard let opcodeByte = pduData.first
                else { fatalError("Empty data \(pduData)") }
            
            guard let opcode = ATTOpcode(rawValue: opcodeByte)
                else { fatalError("Invalid opcode \(opcodeByte)") }
            
            switch opcode.type.destination {
                
            case .client:
                
                clientSocketData.append(Data(pduData))
                
            case .server:
                
                serverSocketData.append(Data(pduData))
            }
        }
        
        return (serverSocketData, clientSocketData)
    }
}

fileprivate extension ATTOpcodeType {
    
    enum Destination {
        
        case client
        case server
    }
    
    var destination: Destination {
        
        switch self {
            
        case .command,
             .request:
            
            return .server
            
        case .response,
             .confirmation,
             .indication,
             .notification:
            
            return .client
        }
    }
}
