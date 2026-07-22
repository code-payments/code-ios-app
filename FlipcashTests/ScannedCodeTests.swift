//
//  ScannedCodeTests.swift
//  FlipcashTests
//

import Testing
import Foundation
@testable import Flipcash
@testable import FlipcashCore

@Suite("ScannedCode kind dispatch")
struct ScannedCodeTests {

    private func cashFrame() -> (payload: CashCode.Payload, data: Data) {
        let payload = CashCode.Payload(
            kind: .cash,
            fiat: FiatAmount(value: 5, currency: .usd),
            nonce: Data(repeating: 0x07, count: Data.nonceLength)
        )
        return (payload, payload.encode())
    }

    @Test("A cash frame dispatches to the cash payload")
    func cashFrameDispatches() throws {
        let (payload, data) = cashFrame()

        guard case .cash(let decoded)? = ScannedCode(data: data) else {
            Issue.record("Expected a cash payload")
            return
        }
        #expect(decoded == payload)
    }

    @Test("A tip frame dispatches to the tip payload")
    func tipFrameDispatches() throws {
        let userID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let data = TipCode.Payload(userID: userID).encode()

        guard case .tip(let decoded)? = ScannedCode(data: data) else {
            Issue.record("Expected a tip payload")
            return
        }
        #expect(decoded.userID == userID)
    }

    @Test("A tip frame whose trailing zeros were stripped still decodes")
    func shortTipFrameDecodes() throws {
        let userID = UUID(uuidString: "11111111-2222-3333-4444-555500000000")!
        var data = TipCode.Payload(userID: userID).encode()
        while data.last == 0 {
            data.removeLast()
        }

        guard case .tip(let decoded)? = ScannedCode(data: data) else {
            Issue.record("Expected a tip payload from a stripped frame")
            return
        }
        #expect(decoded.userID == userID)
    }

    @Test("Unknown kinds and malformed frames return nil", arguments: [
        Data(),
        Data([9]),
        Data(repeating: 0xFF, count: 20),
        Data(repeating: 0xFF, count: 40),
    ])
    func malformedFramesReturnNil(_ data: Data) {
        #expect(ScannedCode(data: data) == nil)
    }
}
