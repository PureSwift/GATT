//
//  LinuxCentral.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 1/22/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

#if os(Linux) || (Xcode && SWIFT_PACKAGE)
    
import Foundation
import Bluetooth
import BluetoothLinux
    
@available(OSX 10.12, *)
public final class LinuxCentral: CentralProtocol {
        
        public var log: ((String) -> ())?
        
        public init() {
            
            fatalError()
        }
        
        public func scan(filterDuplicates: Bool = true, shouldContinueScanning: () -> (Bool), foundDevice: @escaping (ScanData) -> ()) throws {
            
            fatalError()
        }
        
        public func connect(to peripheral: Peripheral, timeout: TimeInterval = 30) throws {
            
        }
        
        public func discoverServices(_ services: [BluetoothUUID] = [], for peripheral: Peripheral, timeout: TimeInterval = 30) throws -> [Service] {
            
            fatalError()
        }
        
        public func discoverCharacteristics(_ characteristics: [BluetoothUUID] = [], for service: BluetoothUUID, peripheral: Peripheral, timeout: TimeInterval = 30) throws -> [Characteristic] {
            
            
            fatalError()
        }
        
        public func readValue(for characteristic: BluetoothUUID, service: BluetoothUUID, peripheral: Peripheral, timeout: TimeInterval = 30) throws -> Data {
            
            fatalError()
        }
        
        public func writeValue(_ data: Data, for characteristic: BluetoothUUID, withResponse: Bool = true, service: BluetoothUUID, peripheral: Peripheral, timeout: TimeInterval = 30) throws {
            
            fatalError()
        }
        
        public func notify(_ notification: ((Data) -> ())?, for characteristic: BluetoothUUID, service: BluetoothUUID, peripheral: Peripheral, timeout: TimeInterval = 30) throws {
            
            fatalError()
        }
    
        public func disconnect(peripheral: Peripheral) {
            
            fatalError()
        }
    
        public func disconnectAll() {
        
            fatalError()
        }
    }

#endif

#if os(Linux)
    
    /// The platform specific peripheral.
    public typealias CentralManager = LinuxCentral
    
#endif
