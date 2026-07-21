//
//  TipCodeEncodingTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
import CodeScanner
@testable import Flipcash

struct TipCodeEncodingTests {

    /// Fixed rather than random: Swift Testing reruns individual arguments, so a
    /// per-run UUID would leave a failure with no reproducer. Chosen
    /// structurally — all-zero, all-ones, a high first byte, interior nulls, a
    /// real v4, and the max v4.
    private static let userIDs: [UUID] = [
        UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
        UUID(uuidString: "ffffffff-ffff-ffff-ffff-ffffffffffff")!,
        UUID(uuidString: "80000000-0000-0000-0000-0000000000ff")!,
        UUID(uuidString: "3f2504e0-0000-11d3-0000-0305e82c3301")!,
        UUID(uuidString: "3f2504e0-4f89-41d3-9a0c-0305e82c3301")!,
        UUID(uuidString: "ffffffff-ffff-4fff-bfff-ffffffffffff")!,
    ]

    // MARK: - Round-trip -

    @Test("Round-trip preserves the user id", arguments: TipCodeEncodingTests.userIDs)
    func roundTripPreservesUserID(userID: UUID) throws {
        let payload = TipCode.Payload(userID: userID)

        let decoded = try TipCode.Payload(data: payload.encode())

        #expect(decoded == payload)
        #expect(decoded.userID == userID)
    }

    /// `KikCodes.decode` strips trailing zero bytes, so a user id ending in
    /// zeros survives the code as a SHORT frame. The decoder has to restore it —
    /// the scanner hands `KikCodes.decode` output straight to the initializer
    /// (`CodeExtractor.processSample`), with no padding in between.
    @Test("Round-trip survives the scannable code, which strips trailing zeros",
          arguments: TipCodeEncodingTests.userIDs)
    func roundTripThroughKikCode(userID: UUID) throws {
        let payload = TipCode.Payload(userID: userID)

        let scanned = KikCodes.decode(KikCodes.encode(payload.encode()))

        #expect(scanned.count <= TipCode.Payload.length)
        #expect(try TipCode.Payload(data: scanned) == payload)
    }

    @Test("A zero-stripped frame decodes to the same user id")
    func decodesAZeroStrippedFrame() throws {
        let userID = UUID(uuidString: "3f2504e0-4f89-41d3-9a0c-000000000000")!
        let payload = TipCode.Payload(userID: userID)

        var truncated = payload.encode()
        while truncated.last == 0 { truncated.removeLast() }

        #expect(truncated.count < TipCode.Payload.length)
        #expect(try TipCode.Payload(data: truncated) == payload)
    }

    // MARK: - Frame -

    @Test("The payload fills the shared 20-byte frame", arguments: TipCodeEncodingTests.userIDs)
    func encodesToTheSharedFrameLength(userID: UUID) {
        let encoded = TipCode.Payload(userID: userID).encode()

        #expect(encoded.count == TipCode.Payload.length)
        #expect(encoded.count == CashCode.Payload.length)
    }

    @Test("The trailing bytes are reserved and zeroed", arguments: TipCodeEncodingTests.userIDs)
    func reservedBytesAreZero(userID: UUID) {
        let encoded = TipCode.Payload(userID: userID).encode()

        #expect(encoded[0] == TipCode.Payload.kind)
        #expect(encoded[17...].allSatisfy { $0 == 0 })
    }

    // MARK: - Rejection -

    /// Short frames are legitimate (see the zero-stripping above); empty and
    /// over-long ones are not.
    @Test("A frame of the wrong length is rejected", arguments: [0, 21, 40])
    func rejectsWrongLength(count: Int) {
        #expect(throws: TipCode.Payload.Error.invalidDataSize) {
            try TipCode.Payload(data: Data(count: count))
        }
    }

    @Test("A frame carrying another kind is rejected", arguments: [UInt8(0), 1, 3, 255])
    func rejectsForeignKindByte(kind: UInt8) {
        var data = Data(count: TipCode.Payload.length)
        data[0] = kind

        #expect(throws: TipCode.Payload.Error.invalidKind) {
            try TipCode.Payload(data: data)
        }
    }

    /// The whole reason `TipCode.Payload` is a sibling of `CashCode.Payload`
    /// rather than a kind on it: one scanner dispatches on byte 0, so a tip
    /// frame must never decode as cash — that would fabricate a rendezvous key
    /// and a fiat amount on a real-money path.
    @Test("The tip kind byte is disjoint from every cash kind")
    func tipKindIsDisjointFromCashKinds() {
        #expect(CashCode.Payload.Kind(rawValue: TipCode.Payload.kind) == nil)
    }

    @Test("The cash decoder refuses a tip frame")
    func cashDecoderRejectsATipFrame() {
        let tipFrame = TipCode.Payload(userID: Self.userIDs.last!).encode()

        #expect(throws: CashCode.Payload.Error.invalidKind) {
            try CashCode.Payload(data: tipFrame)
        }
    }
}
