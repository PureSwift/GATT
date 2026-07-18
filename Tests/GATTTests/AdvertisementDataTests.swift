//
//  AdvertisementDataTests.swift
//  GATT
//
//  Created by Alsey Coleman Miller on 7/17/26.
//  Copyright © 2026 PureSwift. All rights reserved.
//

#if canImport(BluetoothGAP)
import Foundation
import XCTest
import Bluetooth
import BluetoothGAP
@testable import GATT

final class AdvertisementDataTests: XCTestCase {

    typealias Encoder = GAPDataEncoder<LowEnergyAdvertisingData>

    func testLocalName() {

        let complete: LowEnergyAdvertisingData = Encoder.encode([GAPCompleteLocalName(name: "Complete")])
        XCTAssertEqual(complete.localName, "Complete")

        let short: LowEnergyAdvertisingData = Encoder.encode([GAPShortLocalName(name: "Short")])
        XCTAssertEqual(short.localName, "Short")
    }

    func testManufacturerData() {

        let manufacturerData = GAPManufacturerSpecificData<LowEnergyAdvertisingData>(
            companyIdentifier: 0x004C,
            additionalData: [0x01, 0x02]
        )
        let advertisement: LowEnergyAdvertisingData = Encoder.encode([manufacturerData])

        let decoded = advertisement.manufacturerData
        XCTAssertEqual(decoded?.companyIdentifier, 0x004C)
        XCTAssertEqual(decoded?.additionalData, [0x01, 0x02] as LowEnergyAdvertisingData)
    }

    func testTxPowerLevel() {

        guard let powerLevel = GAPTxPowerLevel(powerLevel: -20) else {
            XCTFail("Invalid power level")
            return
        }
        let advertisement: LowEnergyAdvertisingData = Encoder.encode([powerLevel])
        XCTAssertEqual(advertisement.txPowerLevel, -20.0)
    }

    func testServiceData() {

        let serviceData = GAPServiceData16BitUUID<LowEnergyAdvertisingData>(
            uuid: 0x180F,
            serviceData: [0x99]
        )
        let advertisement: LowEnergyAdvertisingData = Encoder.encode([serviceData])

        let decoded = advertisement.serviceData
        XCTAssertEqual(decoded?.count, 1)
        XCTAssertNotNil(decoded?[.bit16(0x180F)])
    }

    func testServiceUUIDs() {

        let advertisement: LowEnergyAdvertisingData = Encoder.encode([
            GAPCompleteListOf16BitServiceClassUUIDs(uuids: [0x180F, 0x180A])
        ])
        let uuids = advertisement.serviceUUIDs
        XCTAssertEqual(uuids?.count, 2)
        XCTAssert(uuids?.contains(.bit16(0x180F)) == true)
        XCTAssert(uuids?.contains(.bit16(0x180A)) == true)
    }

    func testSolicitedServiceUUIDs() {

        let advertisement: LowEnergyAdvertisingData = Encoder.encode([
            GAPListOf16BitServiceSolicitationUUIDs(uuids: [0x1234])
        ])
        let uuids = advertisement.solicitedServiceUUIDs
        XCTAssertEqual(uuids?.count, 1)
        XCTAssert(uuids?.contains(.bit16(0x1234)) == true)
    }

    func testEmpty() {

        let advertisement = LowEnergyAdvertisingData()
        XCTAssertNil(advertisement.localName)
        XCTAssertNil(advertisement.manufacturerData)
        XCTAssertNil(advertisement.txPowerLevel)
        XCTAssertNil(advertisement.serviceData)
        XCTAssertNil(advertisement.serviceUUIDs)
        XCTAssertNil(advertisement.solicitedServiceUUIDs)
    }
}

#endif
