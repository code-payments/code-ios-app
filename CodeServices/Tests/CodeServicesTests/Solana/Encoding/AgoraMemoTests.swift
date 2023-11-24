//
//  AgoraMemoTests.swift
//  CodeServicesTests
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import XCTest
import CodeServices

class AgoraMemoTests: XCTestCase {

    func testEncodingSpecificData() throws {
        let memo = AgoraMemo(
            magicByte: .default,
            version: 2,
            transferType: .p2p,
            appIndex: 10,
            bytes: [0xAE, 0xFD]
        )

        let decoded = try AgoraMemo(data: memo.encode())

        XCTAssertEqual(memo.bytes, decoded.bytes)
    }

    func testEncodingValidDataLessThanMax() throws {
        let memo = AgoraMemo(
            magicByte: .default,
            version: 2,
            transferType: .p2p,
            appIndex: 10,
            bytes: [Byte](UUID().uuidString.data(using: .utf8)!)
        )

        let decoded = try AgoraMemo(data: memo.encode())

        XCTAssertEqual(memo.bytes, decoded.bytes)
    }

    func testEncodingValidDataLargerThanMax() throws {
        let foreignKeyBytes = [Byte](UUID().uuidString.utf8) + [Byte](UUID().uuidString.utf8)
        
        let memo = AgoraMemo(
            magicByte: .default,
            version: 2,
            transferType: .p2p,
            appIndex: 10,
            bytes: foreignKeyBytes
        )

        let decoded = try AgoraMemo(data: memo.encode())

        XCTAssertEqual(decoded.bytes, [Byte](foreignKeyBytes[0..<28]))
    }

    func testEncodingappIndexValidRange() throws {
        let appIndexes: [UInt16] = [0, 10_000, 65_535]
        let foreignKeyBytes = [Byte](UUID().uuidString.utf8)
        
        for appIndex in appIndexes {

            let memo = AgoraMemo(
                magicByte: .default,
                version: 7,
                transferType: .p2p,
                appIndex: appIndex,
                bytes: foreignKeyBytes
            )

            let decoded = try AgoraMemo(data: memo.encode())

            XCTAssertEqual(decoded.magicByte, .default)
            XCTAssertEqual(decoded.version, 7)
            XCTAssertEqual(decoded.transferType, AgoraMemo.TransferType.p2p)
            XCTAssertEqual(decoded.appIndex, appIndex)
            XCTAssertEqual(decoded.bytes, memo.bytes)
        }
    }

    func testInitEmptyForeignKeyBytes() {
        let memo = AgoraMemo(
            magicByte: .default,
            version: 7,
            transferType: .earn,
            appIndex: 65535,
            bytes: []
        )
        
        let bytes = [Byte].zeroed(with: 28)

        XCTAssertEqual(memo.bytes, bytes)
    }
}
