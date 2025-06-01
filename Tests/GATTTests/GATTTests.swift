//
//  GATTTests.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 7/12/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

#if canImport(BluetoothGATT)
import Foundation
import XCTest
import Bluetooth
import BluetoothHCI
@testable import BluetoothGATT
@testable import GATT

final class GATTTests: XCTestCase {
    
    typealias TestPeripheral = GATTPeripheral<TestHostController, TestL2CAPServer>
    typealias TestCentral = GATTCentral<TestHostController, TestL2CAPSocket>
    
    func testScanData() {
        
        do {
            
            /**
             HCI Event RECV  0x0000  94:E3:6D:62:1E:01  LE Meta Event - LE Advertising Report - 0 - 94:E3:6D:62:1E:01  -65 dBm - Type 2
             
             Parameter Length: 42 (0x2A)
             Num Reports: 0X01
             Event Type: Connectable undirected advertising (ADV_IND)
             Address Type: Public
             Peer Address: 94:E3:6D:62:1E:01
             Length Data: 0X1E
             Flags: 0X06
             Apple Manufacturing Data
             Length: 26 (0x1A)
             Data: 02 01 06 1A FF 4C 00 02 15 FD A5 06 93 A4 E2 4F B1 AF CF C6 EB 07 64 78 25 27 12 0B 86 BE
             RSSI: -65 dBm
             */
            
            let data = Data([/* 0x3E, 0x2A, 0x02, */ 0x01, 0x00, 0x00, 0x01, 0x1E, 0x62, 0x6D, 0xE3, 0x94, 0x1E, 0x02, 0x01, 0x06, 0x1A, 0xFF, 0x4C, 0x00, 0x02, 0x15, 0xFD, 0xA5, 0x06, 0x93, 0xA4, 0xE2, 0x4F, 0xB1, 0xAF, 0xCF, 0xC6, 0xEB, 0x07, 0x64, 0x78, 0x25, 0x27, 0x12, 0x0B, 0x86, 0xBE, 0xBF])
            
            guard let advertisingReports = HCILEAdvertisingReport(data: data),
                let report = advertisingReports.reports.first
                else { XCTFail("Could not parse HCI event"); return }
            
            XCTAssertEqual(report.event.isConnectable, true)
            
            let peripheral = Peripheral(id: report.address)
            
            let scanData = ScanData(
                peripheral: peripheral,
                date: Date(),
                rssi: -65.0,
                advertisementData: report.responseData,
                isConnectable: report.event.isConnectable
            )
            
            XCTAssertEqual(scanData.peripheral.id.rawValue, "94:E3:6D:62:1E:01")
        }
    }
    
    func testMTUExchange() async throws {
        
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
        let mockData = split(pdu: testPDUs.map { $0.1 })
        
        try await connect(
            serverOptions: GATTPeripheralOptions(
                maximumTransmissionUnit: serverMTU,
                maximumPreparedWrites: .max
            ),
            clientOptions: GATTCentralOptions(
                maximumTransmissionUnit: clientMTU
            ),
            client: { (central, peripheral) in
                let services = try await central.discoverServices(for: peripheral)
                XCTAssertEqual(services.count, 0)
                let clientMTU = try await central.maximumTransmissionUnit(for: peripheral)
                XCTAssertEqual(clientMTU, finalMTU)
                let maximumUpdateValueLength = await central.storage.connections.first?.value.connection.maximumUpdateValueLength
                XCTAssertEqual(maximumUpdateValueLength, Int(finalMTU.rawValue) - 3)
                let clientCache = await central.storage.connections.values.first?.connection.client.connection.socket.cache
                XCTAssertEqual(clientCache?.prefix(1), mockData.client.prefix(1)) // not same because extra service discovery request
            }
        )
    }
    
    func testServiceDiscovery() async throws {
        
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
            (ATTReadByGroupTypeRequest(startHandle: 0x0001, endHandle: 0xffff, type: BluetoothUUID.Declaration.primaryService),
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
                                                         value: Data(BluetoothUUID.Service.battery.littleEndian))
                ])!,
            [0x11, 0x06, 0x01, 0x00, 0x04, 0x00, 0x0F, 0x18]),
            /**
             Read By Group Type Request - Start Handle:0x0005 - End Handle:0xffff - UUID:2800 (GATT Primary Service Declaration)
             Opcode: 0x10
             Starting Handle: 0x0005
             Ending Handle: 0xffff
             Attribute Group Type: 2800 (GATT Primary Service Declaration)
             */
            (ATTReadByGroupTypeRequest(startHandle: 0x0005, endHandle: 0xffff, type: BluetoothUUID.Declaration.primaryService),
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
        let mockData = split(pdu: testPDUs.map { $0.1 })
        
        // service
        let batteryLevel = GATTBatteryLevel(level: .min)
        
        let characteristics = [
            GATTAttribute<Data>.Characteristic(
                uuid: type(of: batteryLevel).uuid,
                value: batteryLevel.data,
                permissions: [.read],
                properties: [.read, .notify],
                descriptors: [.init(GATTClientCharacteristicConfiguration(), permissions: [.read, .write])])
        ]
        
        let service = GATTAttribute<Data>.Service(
            uuid: BluetoothUUID.Service.battery,
            isPrimary: true,
            characteristics: characteristics
        )
        
        try await connect(
            serverOptions: GATTPeripheralOptions(
                maximumTransmissionUnit: serverMTU,
                maximumPreparedWrites: .max
            ),
            clientOptions: GATTCentralOptions(
                maximumTransmissionUnit: clientMTU
            ), server: { peripheral in
                _ = peripheral.add(service: service)
            }, client: { (central, peripheral) in
                let services = try await central.discoverServices(for: peripheral)
                let clientMTU = try await central.maximumTransmissionUnit(for: peripheral)
                XCTAssertEqual(clientMTU, finalMTU)
                guard let foundService = services.first,
                    services.count == 1
                    else { XCTFail(); return }
                XCTAssertEqual(foundService.uuid, BluetoothUUID.Service.battery)
                XCTAssertEqual(foundService.isPrimary, true)
                let clientCache = await central.storage.connections.values.first?.connection.client.connection.socket.cache
                XCTAssertEqual(clientCache, mockData.client)
            }
        )
        
        /*
        XCTAssertEqual(peripheral.connections.values.first?.maximumUpdateValueLength, Int(finalMTU.rawValue) - 3)
        XCTAssertEqual(central.connections.values.first?.maximumUpdateValueLength, Int(finalMTU.rawValue) - 3)
        
        // validate GATT PDUs
        let mockData = split(pdu: testPDUs.map { $0.1 })
        XCTAssertEqual(serverSocket.cache, mockData.server)
        XCTAssertEqual(clientSocket.cache, mockData.client)
        */
    }
    
    func testCharacteristicValue() async throws {
        
        // service
        let batteryLevel = GATTBatteryLevel(level: .max)
        
        let characteristics = [
            GATTAttribute<Data>.Characteristic(
                uuid: type(of: batteryLevel).uuid,
                value: batteryLevel.data,
                permissions: [.read, .write],
                properties: [.read, .write],
                descriptors: []
            )
        ]
        
        let service = GATTAttribute<Data>.Service(
            uuid: BluetoothUUID.Service.battery,
            isPrimary: true,
            characteristics: characteristics
        )

        let newValue = GATTBatteryLevel(level: .min)
        
        var serviceAttribute: UInt16!
        var characteristicValueHandle: UInt16!
        var peripheralDatabaseValue: (() async -> (Data))!
        
        try await connect(
            server: { peripheral in
                let (serviceAttributeHandle, characteristicValueHandles) = peripheral.add(service: service)
                serviceAttribute = serviceAttributeHandle
                XCTAssertEqual(serviceAttribute, 1)
                characteristicValueHandle = characteristicValueHandles[0]
                peripheralDatabaseValue = { peripheral[characteristic: characteristicValueHandle] }
                let currentValue = await peripheralDatabaseValue()
                XCTAssertEqual(currentValue, characteristics[0].value)
                peripheral.willWrite = {
                    XCTAssertEqual($0.uuid, BluetoothUUID.Characteristic.batteryLevel)
                    XCTAssertEqual($0.value, batteryLevel.data)
                    XCTAssertEqual($0.newValue, newValue.data)
                    return nil
                }
                peripheral.didWrite = {
                    XCTAssertEqual($0.uuid, BluetoothUUID.Characteristic.batteryLevel)
                    XCTAssertEqual($0.value, newValue.data)
                }
            },
            client: { (central, peripheral) in
                let services = try await central.discoverServices(for: peripheral)
                let clientMTU = try await central.maximumTransmissionUnit(for: peripheral)
                XCTAssertEqual(clientMTU, .default)
                guard let foundService = services.first,
                    services.count == 1
                    else { XCTFail(); return }
                XCTAssertEqual(foundService.uuid, BluetoothUUID.Service.battery)
                XCTAssertEqual(foundService.isPrimary, true)
                let foundCharacteristics = try await central.discoverCharacteristics(for: foundService)
                guard let foundCharacteristic = foundCharacteristics.first,
                    foundCharacteristics.count == 1
                    else { XCTFail(); return }
                XCTAssertEqual(foundCharacteristic.uuid, BluetoothUUID.Characteristic.batteryLevel)
                XCTAssertEqual(foundCharacteristic.properties, [.read, .write])
                // read value
                let characteristicData = try await central.readValue(for: foundCharacteristic)
                guard let characteristicValue = GATTBatteryLevel(data: characteristicData)
                    else { XCTFail(); return }
                XCTAssertEqual(characteristicValue, batteryLevel)
                // write value
                try await central.writeValue(newValue.data, for: foundCharacteristic, withResponse: true)
                // validate
                let currentValue = await peripheralDatabaseValue()
                XCTAssertEqual(currentValue, newValue.data)
                XCTAssertNotEqual(currentValue, characteristics[0].value)
                XCTAssertNotEqual(currentValue, characteristicValue.data)
            }
        )
    }
    
    func testNotification() async throws {
        
        // service
        let batteryLevel = GATTBatteryLevel(level: .max)
        
        let characteristics = [
            GATTAttribute<Data>.Characteristic(
                uuid: type(of: batteryLevel).uuid,
                value: batteryLevel.data,
                permissions: [.read],
                properties: [.read, .notify],
                descriptors: [.init(GATTClientCharacteristicConfiguration(), permissions: [.read, .write])]
            )
        ]
        
        let service = GATTAttribute<Data>.Service(
            uuid: BluetoothUUID.Service.battery,
            isPrimary: true,
            characteristics: characteristics
        )

        let newValue = GATTBatteryLevel(level: .min)
                
        try await connect(
            serverOptions: .init(maximumTransmissionUnit: .default, maximumPreparedWrites: 1000),
            clientOptions: .init(maximumTransmissionUnit: .max),
            server: { peripheral in
                let (serviceAttribute, characteristicValueHandles) = peripheral.add(service: service)
                XCTAssertEqual(serviceAttribute, 1)
                let characteristicValueHandle = characteristicValueHandles[0]
                Task {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    peripheral.write(newValue.data, forCharacteristic: characteristicValueHandle)
                }
            },
            client: { (central, peripheral) in
                let services = try await central.discoverServices(for: peripheral)
                let clientMTU = try await central.maximumTransmissionUnit(for: peripheral)
                XCTAssertEqual(clientMTU, .default)
                guard let foundService = services.first,
                    services.count == 1
                    else { XCTFail(); return }
                XCTAssertEqual(foundService.uuid, BluetoothUUID.Service.battery)
                XCTAssertEqual(foundService.isPrimary, true)
                let foundCharacteristics = try await central.discoverCharacteristics(for: foundService)
                guard let foundCharacteristic = foundCharacteristics.first,
                    foundCharacteristics.count == 1
                    else { XCTFail(); return }
                XCTAssertEqual(foundCharacteristic.uuid, BluetoothUUID.Characteristic.batteryLevel)
                XCTAssertEqual(foundCharacteristic.properties, [.read, .notify])
                // wait for notifications
                let stream = central.notify(for: foundCharacteristic)
                for try await notification in stream {
                    guard let notificationValue = GATTBatteryLevel(data: notification) else {
                        XCTFail();
                        return
                    }
                    XCTAssertEqual(notificationValue, newValue)
                    stream.stop()
                    break
                }
            }
        )
    }
    
    func testIndication() async throws {
        
        // service
        let batteryLevel = GATTBatteryLevel(level: .max)
        
        let characteristics = [
            GATTAttribute<Data>.Characteristic(
                uuid: type(of: batteryLevel).uuid,
                value: batteryLevel.data,
                permissions: [.read],
                properties: [.read, .indicate],
                descriptors: [.init(GATTClientCharacteristicConfiguration(), permissions: [.read, .write])]
            )
        ]
        
        let service = GATTAttribute<Data>.Service(
            uuid: BluetoothUUID.Service.battery,
            isPrimary: true,
            characteristics: characteristics
        )

        let newValue = GATTBatteryLevel(level: .min)
        
        try await connect(
            serverOptions: .init(maximumTransmissionUnit: .default, maximumPreparedWrites: 1000),
            clientOptions: .init(maximumTransmissionUnit: .max),
            server: { peripheral in
                let (serviceAttribute, characteristicValueHandles) = peripheral.add(service: service)
                XCTAssertEqual(serviceAttribute, 1)
                let characteristicValueHandle = characteristicValueHandles[0]
                Task {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    peripheral.write(newValue.data, forCharacteristic: characteristicValueHandle)
                }
            },
            client: { (central, peripheral) in
                let services = try await central.discoverServices(for: peripheral)
                let clientMTU = try await central.maximumTransmissionUnit(for: peripheral)
                XCTAssertEqual(clientMTU, .default)
                guard let foundService = services.first,
                    services.count == 1
                    else { XCTFail(); return }
                XCTAssertEqual(foundService.uuid, BluetoothUUID.Service.battery)
                XCTAssertEqual(foundService.isPrimary, true)
                let foundCharacteristics = try await central.discoverCharacteristics(for: foundService)
                guard let foundCharacteristic = foundCharacteristics.first,
                    foundCharacteristics.count == 1
                    else { XCTFail(); return }
                XCTAssertEqual(foundCharacteristic.uuid, BluetoothUUID.Characteristic.batteryLevel)
                XCTAssertEqual(foundCharacteristic.properties, [.read, .indicate])
                // wait for notifications
                let stream = central.notify(for: foundCharacteristic)
                for try await notification in stream {
                    guard let notificationValue = GATTBatteryLevel(data: notification) else {
                        XCTFail();
                        return
                    }
                    XCTAssertEqual(notificationValue, newValue)
                    stream.stop()
                    break
                }
            }
        )
    }
    
    func testDescriptors() async throws {
        
        let descriptors = [
            .init(GATTClientCharacteristicConfiguration(), permissions: [.read, .write]),
            //GATTUserDescription(userDescription: "Characteristic").descriptor,
            GATTAttribute<Data>.Descriptor(uuid: BluetoothUUID(),
                                     value: Data("UInt128 Descriptor".utf8),
                                     permissions: [.read, .write]),
            GATTAttribute<Data>.Descriptor(uuid: BluetoothUUID.Member.savantSystems,
                                         value: Data("Savant".utf8),
                                         permissions: [.read]),
            GATTAttribute<Data>.Descriptor(uuid: BluetoothUUID.Member.savantSystems2,
                                         value: Data("Savant2".utf8),
                                         permissions: [.write])
        ]
        
        let characteristic = GATTAttribute<Data>.Characteristic(uuid: BluetoothUUID(),
                                                 value: Data(),
                                                 permissions: [.read],
                                                 properties: [.read],
                                                 descriptors: descriptors)
        
        let service = GATTAttribute<Data>.Service(
            uuid: BluetoothUUID(),
            isPrimary: true,
            characteristics: [characteristic]
        )
        
        try await connect(
            serverOptions: .init(maximumTransmissionUnit: .default, maximumPreparedWrites: 1000),
            clientOptions: .init(maximumTransmissionUnit: .default),
            server: { peripheral in
                let (serviceAttribute, _) = peripheral.add(service: service)
                XCTAssertEqual(serviceAttribute, 1)
            },
            client: { (central, peripheral) in
                let services = try await central.discoverServices(for: peripheral)
                let clientMTU = try await central.maximumTransmissionUnit(for: peripheral)
                XCTAssertEqual(clientMTU, .default)
                guard let foundService = services.first,
                    services.count == 1
                    else { XCTFail(); return }
                XCTAssertEqual(foundService.uuid, service.uuid)
                XCTAssertEqual(foundService.isPrimary, true)
                
                let foundCharacteristics = try await central.discoverCharacteristics(for: foundService)
                XCTAssertEqual(foundCharacteristics.count, 1)
                guard let foundCharacteristic = foundCharacteristics.first else { XCTFail(); return }
                XCTAssertEqual(foundCharacteristic.uuid, characteristic.uuid)
                let foundDescriptors = try await central.discoverDescriptors(for: foundCharacteristic)
                XCTAssertEqual(foundDescriptors.count, descriptors.count)
                XCTAssertEqual(foundDescriptors.map { $0.uuid }, descriptors.map { $0.uuid })
                
                for (index, descriptor) in foundDescriptors.enumerated() {
                    let expectedValue = descriptors[index].value
                    let descriptorPermissions = descriptors[index].permissions
                    if descriptorPermissions.contains(.read) {
                        let readValue = try await central.readValue(for: descriptor)
                        XCTAssertEqual(readValue, expectedValue)
                    }
                    if descriptorPermissions.contains(.write) {
                        let newValue = Data("new value".utf8)
                        try await central.writeValue(newValue, for: descriptor)
                        if descriptorPermissions.contains(.read) {
                            let newServerValue = try await central.readValue(for: descriptor)
                            XCTAssertEqual(newValue, newServerValue)
                        }
                    }
                }
            }
        )
    }
    
}

extension GATTTests {
    
    func connect(
        serverOptions: GATTPeripheralOptions = .init(),
        clientOptions: GATTCentralOptions = .init(),
        advertisingReports: [Data] = [
            Data([0x3E, 0x2A, 0x02, 0x01, 0x00, 0x00, 0x01, 0x1E, 0x62, 0x6D, 0xE3, 0x94, 0x1E, 0x02, 0x01, 0x06, 0x1A, 0xFF, 0x4C, 0x00, 0x02, 0x15, 0xFD, 0xA5, 0x06, 0x93, 0xA4, 0xE2, 0x4F, 0xB1, 0xAF, 0xCF, 0xC6, 0xEB, 0x07, 0x64, 0x78, 0x25, 0x27, 0x12, 0x0B, 0x86, 0xBE, 0xBF])
        ],
        server: (TestPeripheral) async throws -> () = { _ in },
        client: (TestCentral, Peripheral) async throws -> (),
        file: StaticString = #file,
        line: UInt = #line
    ) async throws {
        
        guard let reportData = advertisingReports.first?.suffix(from: 3),
            let report = HCILEAdvertisingReport(data: Data(reportData)) else {
            XCTFail("No scanned devices", file: file, line: line)
            return
        }
        
        // host controller
        let serverHostController = TestHostController(address: report.reports.first!.address)
        let clientHostController = TestHostController(address: .min)
        
        // peripheral
        let peripheral = TestPeripheral(
            hostController: serverHostController,
            options: serverOptions,
            socket: TestL2CAPServer.self
        )
        peripheral.log = { print("Peripheral:", $0) }
        try await server(peripheral)
        
        peripheral.start()
        defer { peripheral.stop() }
        
        // central
        let central = TestCentral(
            hostController: clientHostController,
            options: clientOptions,
            socket: TestL2CAPSocket.self
        )
        central.log = { print("Central:", $0) }
        central.hostController.advertisingReports = advertisingReports
        
        let scan = try await central.scan(filterDuplicates: true)
        guard let device = try await scan.first()
            else { XCTFail("No devices scanned"); return }
        
        // connect and execute
        try await central.connect(to: device.peripheral)
        try await client(central, device.peripheral)
        // cleanup
        await central.disconnectAll()
        peripheral.removeAllServices()
    }
    
    func test(
        _ testPDUs: [(ATTProtocolDataUnit, [UInt8])],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        
        // decode and compare
        for (testPDU, testData) in testPDUs {
            
            guard let decodedPDU = type(of: testPDU).init(data: testData)
                else { XCTFail("Could not decode \(type(of: testPDU))"); return }
            
            XCTAssertEqual(Data(decodedPDU), Data(testData), file: file, line: line)
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

#endif
