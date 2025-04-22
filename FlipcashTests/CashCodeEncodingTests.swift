//
//  FlipcashTests.swift
//  FlipcashTests
//
//  Created by Dima Bart on 2025-03-31.
//

import Foundation
import Testing
import FlipcashCore
import CodeScanner
@testable import Flipcash

struct CashCodeEncodingTests {
    
    private static let data = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x10])
    
    @Test static func roundTrip() throws {
        let payload = CashCode.Payload(kind: .cash, fiat: 5, nonce: data)
        let encoded = payload.encode()
        
        let decoded = try CashCode.Payload(data: encoded)

        #expect(payload.kind == decoded.kind)
        #expect(payload.fiat == decoded.fiat)
        #expect(payload.nonce == decoded.nonce)
        
        let encodedCodeData = KikCodes.encode(encoded)
        let decodedCodeData = KikCodes.decode(encodedCodeData)
        
        #expect(encoded == decodedCodeData)
    }
}
