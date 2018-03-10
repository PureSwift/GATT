//
//  TestProfile.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/3/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import Foundation
import Bluetooth

public struct TestProfile {
    
    public typealias Service = GATT.Service
    
    public typealias Characteristic = GATT.Characteristic
    
    public static let services = [TestProfile.TestService]
    
    public static let TestService = Service(uuid: BluetoothUUID(rawValue: "60F14FE2-F972-11E5-B84F-23E070D5A8C7")!, primary: true, characteristics: [TestProfile.Read, TestProfile.ReadBlob, TestProfile.Write, TestProfile.WriteBlob])
    
    public static let Read = Characteristic(uuid: BluetoothUUID(rawValue: "E77D264C-F96F-11E5-80E0-23E070D5A8C7")!, value: "Test Read-Only".toUTF8Data(), permissions: [.read], properties: [.read])
    
    public static let ReadBlob = Characteristic(uuid: BluetoothUUID(rawValue: "0615FF6C-0E37-11E6-9E58-75D7DC50F6B1")!, value: Data(bytes: [UInt8](repeating: UInt8.max, count: 512)), permissions: [.read], properties: [.read])
    
    public static let Write = Characteristic(uuid: BluetoothUUID(rawValue: "37BBD7D0-F96F-11E5-8EC1-23E070D5A8C7")!, value: Data(), permissions: [.write], properties: [.write])
    
    public static let WriteValue = "Test Write".toUTF8Data()
    
    public static let WriteBlob = Characteristic(uuid: BluetoothUUID(rawValue: "2FDDB448-F96F-11E5-A891-23E070D5A8C7")!, value: Data(), permissions: [.write], properties: [.write])
    
    public static let WriteBlobValue = Data(bytes: [UInt8](repeating: 1, count: 512))
}
