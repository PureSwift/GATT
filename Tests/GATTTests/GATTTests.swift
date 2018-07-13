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

final class GATTTests: XCTestCase {
    
    static var allTests = [
        ("testMTUExchange", testMTUExchange),
        ]
    
    func testMTUExchange() {
        
        guard let mtu = ATTMaximumTransmissionUnit(rawValue: 512)
            else { XCTFail(); return }
        
        let testPDUs: [(ATTProtocolDataUnit, [UInt8])] = [
            (ATTMaximumTransmissionUnitRequest(clientMTU: mtu.rawValue),
             [0x02, 0x00, 0x02]),
            (ATTMaximumTransmissionUnitResponse(serverMTU: mtu.rawValue),
             [0x03, 0x00, 0x02])
        ]
        
        // decode and validate bytes
        test(testPDUs)
        
        // setup sockets
        let serverSocket = TestL2CAPSocket()
        let clientSocket = TestL2CAPSocket()
        clientSocket.target = serverSocket
        serverSocket.target = clientSocket // weak references
        
        // peripheral
        let peripheral = TestPeripheral(socket: serverSocket)
        
        // run fake sockets
        do { try run(server: (peripheral.client.server, serverSocket), client: (client, clientSocket)) }
        catch { XCTFail("Error: \(error)") }
        
        XCTAssertEqual(server.connection.maximumTransmissionUnit, client.connection.maximumTransmissionUnit)
        XCTAssertEqual(server.connection.maximumTransmissionUnit, mtu)
        XCTAssertNotEqual(server.connection.maximumTransmissionUnit, .default)
        XCTAssertEqual(client.connection.maximumTransmissionUnit, mtu)
        XCTAssertNotEqual(client.connection.maximumTransmissionUnit, .default)
        
        // validate GATT PDUs
        let mockData = split(pdu: testPDUs.map { $0.1 })
        
        XCTAssertEqual(serverSocket.cache, mockData.server)
        XCTAssertEqual(clientSocket.cache, mockData.client)
    }
}

extension GATTTests {
    
    func test(_ testPDUs: [(ATTProtocolDataUnit, [UInt8])]) {
        
        // decode and compare
        for (testPDU, testData) in testPDUs {
            
            guard let decodedPDU = type(of: testPDU).init(data: Data(testData))
                else { XCTFail("Could not decode \(type(of: testPDU))"); return }
            
            dump(decodedPDU)
            
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
