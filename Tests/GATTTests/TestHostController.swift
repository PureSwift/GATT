//
//  HostController.swift
//  BluetoothTests
//
//  Created by Alsey Coleman Miller on 3/29/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

#if canImport(BluetoothHCI)
import Foundation
import Bluetooth
import BluetoothHCI

final class TestHostController: BluetoothHostControllerInterface {
    
    /// All controllers on the host.
    static var controllers: [TestHostController] { return [TestHostController(address: .min)] }
    
    private(set) var isAdvertising: Bool = false {
        didSet { log?("Advertising \(isAdvertising ? "Enabled" : "Disabled")") }
    }
    
    private(set) var isScanning: Bool = false {
        didSet { log?("Scanning \(isScanning ? "Enabled" : "Disabled")") }
    }
    
    var advertisingReports = [Data]()
    
    var log: ((String) -> ())?
    
    /// The Bluetooth Address of the controller.
    let address: BluetoothAddress
    
    init(address: BluetoothAddress) {
        self.address = address
        self.log = { print("HCI \(address):", $0) }
    }
    
    /// Send an HCI command to the controller.
    func deviceCommand <T: HCICommand> (_ command: T) throws { fatalError() }
    
    /// Send an HCI command with parameters to the controller.
    func deviceCommand <T: HCICommandParameter> (_ commandParameter: T) throws { fatalError() }
    
    /// Send a command to the controller and wait for response.
    func deviceRequest<C: HCICommand>(_ command: C, timeout: HCICommandTimeout) throws { fatalError() }
    
    /// Send a command to the controller and wait for response.
    func deviceRequest <CP: HCICommandParameter> (_ commandParameter: CP, timeout: HCICommandTimeout) throws {
        
        if let command = commandParameter as? HCILESetAdvertiseEnable {
            // check if already enabled
            guard isAdvertising == command.isEnabled
                else { throw HCIError.commandDisallowed }
            // set new value
            self.isAdvertising = command.isEnabled
        }
        else if let command = commandParameter as? HCILESetScanEnable {
            // check if already enabled
            guard isScanning == command.isEnabled
                else { throw HCIError.commandDisallowed }
            // set new value
            self.isScanning = command.isEnabled
        } else {
            
        }
    }
    
    func deviceRequest<C: HCICommand, EP: HCIEventParameter>(_ command: C,
                                                             _ eventParameterType: EP.Type,
                                                             timeout: HCICommandTimeout) throws -> EP {
        fatalError()
    }
    
    /// Sends a command to the device and waits for a response.
    func deviceRequest <CP: HCICommandParameter, EP: HCIEventParameter> (_ commandParameter: CP,
                                                                         _ eventParameterType: EP.Type,
                                                                         timeout: HCICommandTimeout) throws -> EP {
        
        fatalError()
    }
    
    /// Sends a command to the device and waits for a response with return parameter values.
    func deviceRequest <Return: HCICommandReturnParameter> (_ commandReturnType : Return.Type, timeout: HCICommandTimeout) throws -> Return {
        if commandReturnType == HCIReadDeviceAddress.self {
            return HCIReadDeviceAddress(data: self.address.littleEndian.data)! as! Return
        }
        fatalError("\(commandReturnType) not mocked")
    }
    
    /// Sends a command to the device and waits for a response with return parameter values.
    func deviceRequest <CP: HCICommandParameter, Return: HCICommandReturnParameter> (_ commandParameter: CP, _ commandReturnType : Return.Type, timeout: HCICommandTimeout) throws -> Return {
        
        assert(CP.command.opcode == Return.command.opcode)
        fatalError()
    }
    
    /// Polls and waits for events.
    /// Polls and waits for events.
    func recieve<Event>(_ eventType: Event.Type) async throws -> Event where Event : HCIEventParameter, Event.HCIEventType == HCIGeneralEvent {
        
        guard eventType == HCILowEnergyMetaEvent.self
            else { fatalError("Invalid event parameter type") }
        
        while self.advertisingReports.isEmpty {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        
        guard let eventBuffer = self.advertisingReports.popFirst() else {
            fatalError()
        }
        
        let actualBytesRead = eventBuffer.count
        let eventHeader = HCIEventHeader(data: Data(eventBuffer[0 ..< HCIEventHeader.length]))
        let eventData = Data(eventBuffer[HCIEventHeader.length ..< actualBytesRead])
        
        guard let eventParameter = Event.init(data: eventData)
            else { throw BluetoothHostControllerError.garbageResponse(Data(eventData)) }
        
        assert(eventHeader?.event.rawValue == Event.event.rawValue)
        return eventParameter
    }
}

internal extension Array {
    
    mutating func popFirst() -> Element? {
        guard isEmpty == false else { return nil }
        return removeFirst()
    }
}
#endif
