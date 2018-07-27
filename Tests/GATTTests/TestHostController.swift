//
//  HostController.swift
//  BluetoothTests
//
//  Created by Alsey Coleman Miller on 3/29/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import Bluetooth

final class PeripheralHostController: BluetoothHostControllerInterface {
    
    /// All controllers on the host.
    static var controllers: [PeripheralHostController] { return [PeripheralHostController()] }
    
    private(set) var isAdvertising: Bool = false {
        
        didSet { log?("Advertising \(isAdvertising ? "Enabled" : "Disabled")") }
    }
    
    var log: ((String) -> ())?
    
    /// The Bluetooth Address of the controller.
    let address: Address
    
    init(address: Address = .any) {
        
        self.address = address
        self.log = { print("\(type(of: self)):", $0) }
    }
    
    /// Send an HCI command to the controller.
    func deviceCommand <T: HCICommand> (_ command: T) throws { fatalError() }
    
    /// Send an HCI command with parameters to the controller.
    func deviceCommand <T: HCICommandParameter> (_ commandParameter: T) throws { fatalError() }
    
    /// Send a command to the controller and wait for response.
    func deviceRequest<C: HCICommand>(_ command: C, timeout: HCICommandTimeout) throws { fatalError() }
    
    /// Send a command to the controller and wait for response.
    func deviceRequest <CP: HCICommandParameter> (_ commandParameter: CP, timeout: HCICommandTimeout) throws {
        
        guard let command = commandParameter as? HCILESetAdvertiseEnable
            else { fatalError() }
        
        guard isAdvertising == command.isEnabled
            else { throw HCIError.commandDisallowed }
        
        // set new value
        self.isAdvertising = command.isEnabled
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
        
        fatalError()
    }
    
    /// Sends a command to the device and waits for a response with return parameter values.
    func deviceRequest <CP: HCICommandParameter, Return: HCICommandReturnParameter> (_ commandParameter: CP, _ commandReturnType : Return.Type, timeout: HCICommandTimeout) throws -> Return {
        
        assert(CP.command.opcode == Return.command.opcode)
        
        fatalError()
    }
    
    /// Polls and waits for events.
    func pollEvent <T: HCIEventParameter> (_ eventParameterType: T.Type,
                                           shouldContinue: () -> (Bool),
                                           event: (T) throws -> ()) throws {
        
        fatalError()
    }
}

final class CentralHostController: BluetoothHostControllerInterface {
    
    /// All controllers on the host.
    static var controllers: [CentralHostController] { return [CentralHostController()] }
    
    /// The Bluetooth Address of the controller.
    let address: Address
    
    var log: ((String) -> ())?
    
    var scanEvents = [Data]() //[HCILEAdvertisingReport]()
    
    init(address: Address = .any) {
        
        self.address = address
        self.log = { print("\(type(of: self)):", $0) }
    }
    
    /// Send an HCI command to the controller.
    func deviceCommand <T: HCICommand> (_ command: T) throws { }
    
    /// Send an HCI command with parameters to the controller.
    func deviceCommand <T: HCICommandParameter> (_ commandParameter: T) throws { }
    
    /// Send a command to the controller and wait for response.
    func deviceRequest<C: HCICommand>(_ command: C, timeout: HCICommandTimeout) throws { }
    
    /// Send a command to the controller and wait for response.
    func deviceRequest<CP: HCICommandParameter>(_ commandParameter: CP, timeout: HCICommandTimeout) throws { }
    
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
        
        fatalError()
    }
    
    /// Sends a command to the device and waits for a response with return parameter values.
    func deviceRequest <CP: HCICommandParameter, Return: HCICommandReturnParameter> (_ commandParameter: CP, _ commandReturnType : Return.Type, timeout: HCICommandTimeout) throws -> Return {
        
        assert(CP.command.opcode == Return.command.opcode)
        
        fatalError()
    }
    
    /// Polls and waits for events.
    func pollEvent<EP>(_ eventParameterType: EP.Type,
                       shouldContinue: () -> (Bool),
                       event eventCallback: (EP) throws -> ()) throws where EP : HCIEventParameter {
        
        var events = self.scanEvents
        
        while shouldContinue(), let eventData = events.popFirst() {
            
            guard let event = EP.init(data: eventData)
                else { assertionFailure("Invalid data"); return }
            
            try eventCallback(event)
        }
    }
}

internal extension Array {
    
    mutating func popFirst() -> Element? {
        
        guard let first = self.first else { return nil }
        
        self.removeFirst()
        
        return first
    }
}

