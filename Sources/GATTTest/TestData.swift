//
//  TestData.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 4/3/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import SwiftFoundation
import Bluetooth
import GATT

public struct TestData {
    
    public static let testService = TestData.services[0]
    
    public static let writeOnly = (newValue: "NewValue1234".toUTF8Data(), characteristic: TestData.services[3].characteristics[1], service: TestData.services[3].UUID)
    
    public static let services: [Service] = {
        
        var services = [Service]()
        
        do {
            
            let characteristic = Characteristic(UUID: .Bit128(UUID(rawValue: "E77D264C-F96F-11E5-80E0-23E070D5A8C7")!), value: "Test Service".toUTF8Data(), permissions: [.Read], properties: [.Read])
            
            let service = Service(UUID: .Bit128(UUID(rawValue: "60F14FE2-F972-11E5-B84F-23E070D5A8C7")!), primary: true, characteristics: [characteristic])
            
            services.append(service)
        }
        
        do {
            
            let characteristic = Characteristic(UUID: .Bit128(UUID(rawValue: "135BA27C-F96E-11E5-A76B-23E070D5A8C7")!), value: "Hey".toUTF8Data(), permissions: [.Read, .Write], properties: [.Read, .Write])
            
            let characteristic2 = Characteristic(UUID: .Bit128(UUID(rawValue: "088CAF7A-F96F-11E5-9C9A-23E070D5A8C7")!), value: "Hola".toUTF8Data(), permissions: [.Read, .Write], properties: [.Read, .Write])
            
            let service = Service(UUID: .Bit128(UUID(rawValue: "11030276-F96F-11E5-AA7B-23E070D5A8C7")!), characteristics: [characteristic, characteristic2])
            
            services.append(service)
        }
        
        do {
            
            let characteristic = Characteristic(UUID: .Bit128(UUID(rawValue: "16D3B8A8-F96F-11E5-AE5E-23E070D5A8C7")!), value: "Bye".toUTF8Data(), permissions: [.Read, .Write], properties: [.Read, .Write])
            
            let characteristic2 = Characteristic(UUID: .Bit128(UUID(rawValue: "1C9BE9CC-F96F-11E5-A558-23E070D5A8C7")!), value: "Chau".toUTF8Data(), permissions: [.Read, .Write], properties: [.Read, .Write])
            
            let service = Service(UUID: .Bit128(UUID(rawValue: "21C39E9A-F96F-11E5-8CB2-23E070D5A8C7")!), characteristics: [characteristic, characteristic2])
            
            services.append(service)
        }
        
        do {
            
            let characteristic = Characteristic(UUID: .Bit128(UUID(rawValue: "2FDDB448-F96F-11E5-A891-23E070D5A8C7")!), value: "Read Only".toUTF8Data(), permissions: [.Read], properties: [.Read])
            
            let characteristic2 = Characteristic(UUID: .Bit128(UUID(rawValue: "37BBD7D0-F96F-11E5-8EC1-23E070D5A8C7")!), value: "Write Only".toUTF8Data(), permissions: [.Write], properties: [.Write])
            
            let service = Service(UUID: .Bit128(UUID(rawValue: "3D1F4D7E-F96F-11E5-8647-23E070D5A8C7")!), characteristics: [characteristic, characteristic2])
            
            services.append(service)
        }
        
        return services
    }()
}
