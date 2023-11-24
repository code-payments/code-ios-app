//
//  Code.Payload+EncodingTests.swift
//  CodeTests
//
//  Created by Dima Bart on 2021-02-08.
//

import XCTest
import CodeUI
import CodeServices
@testable import Code

class CodePayloadEncodingTests: XCTestCase {
    
    private let data = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x10, 0x11])
    
    private let sampleKin     = Data([0x00, 0x40, 0x4B, 0x4C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x10, 0x11])
    private let sampleFiat    = Data([0x02, 0x8c, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x10, 0x11])
    private let sampleFiatKin = Data([0x02, 0x00, 0x88, 0x13, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x10, 0x11])
    
    private let fiatAmount = Decimal(2_814_749_767_10911) / 100
    
    func testEncodingKin() {
        let payload = Code.Payload(
            kind: .cash,
            kin: 50,
            nonce: data
        )
        
        let encoded = payload.encode()
        
        encoded.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            let base = buffer.baseAddress!
            for offset in 0..<10 {
                XCTAssertEqual(base.advanced(by: offset).load(as: UInt8.self), sampleKin[offset])
            }
        }
    }
    
    func testRoundTripKin() throws {
        let payload = Code.Payload(
            kind: .cash,
            kin: 5_000_000,
            nonce: data
        )
        
        let encoded = payload.encode()
        let decoded = try Code.Payload(data: encoded)
        
        XCTAssertEqual(decoded, payload)
    }
    
    func testEncodingFiat() {
        let payload = Code.Payload(
            kind: .requestPayment,
            fiat: Fiat(currency: .usd, amount: fiatAmount),
            nonce: data
        )
        
        let encoded = payload.encode()
        
        encoded.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            let base = buffer.baseAddress!
            for offset in 0..<10 {
                XCTAssertEqual(base.advanced(by: offset).load(as: UInt8.self), sampleFiat[offset])
            }
        }
    }
    
    func testEncodingFiatWithKin() {
        let payload = Code.Payload(
            kind: .requestPayment,
            fiat: Fiat(currency: .kin, amount: 50.00),
            nonce: data
        )
        
        let encoded = payload.encode()
        
        encoded.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            let base = buffer.baseAddress!
            for offset in 0..<10 {
                XCTAssertEqual(base.advanced(by: offset).load(as: UInt8.self), sampleFiatKin[offset])
            }
        }
    }
    
    func testRoundTripFiat() throws {
        let payload = Code.Payload(
            kind: .requestPayment,
            fiat: Fiat(currency: .cad, amount: 5.00),
            nonce: data
        )
        
        let encoded = payload.encode()
        let decoded = try Code.Payload(data: encoded)
        
        XCTAssertEqual(decoded, payload)
    }
    
    func testDecodingKin() throws {
        let payload = try Code.Payload(data: sampleKin)
        XCTAssertEqual(payload.kind, .cash)
        XCTAssertEqual(payload.value, .kin(50))
        XCTAssertEqual(payload.nonce, data)
    }
    
    func testDecodingFiat() throws {
        let payload = try Code.Payload(data: sampleFiat)
        XCTAssertEqual(payload.kind, .requestPayment)
        XCTAssertEqual(payload.value, .fiat(Fiat(currency: .usd, amount: fiatAmount)))
        XCTAssertEqual(payload.nonce, data)
    }
}
