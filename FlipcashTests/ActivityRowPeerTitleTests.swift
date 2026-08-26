//
//  ActivityRowPeerTitleTests.swift
//  FlipcashTests
//

import Testing
import FlipcashCore
@testable import Flipcash

@Suite("Peer payment row title")
struct ActivityRowPeerTitleTests {

    @Test("A tip keeps the tip phrasing on both sides")
    func tipPhrasing() {
        #expect(ActivityRow.peerTitle(kind: .gave, name: "Sally", serverTitle: "Tipped") == "Tipped Sally")
        #expect(ActivityRow.peerTitle(kind: .received, name: "Sally", serverTitle: "Tipped") == "Tip from Sally")
    }

    @Test("An in-chat send reads as a send, not a tip")
    func sendPhrasing() {
        #expect(ActivityRow.peerTitle(kind: .gave, name: "Sally", serverTitle: "Sent") == "Sent to Sally")
        #expect(ActivityRow.peerTitle(kind: .received, name: "Sally", serverTitle: "Sent") == "Received from Sally")
        #expect(ActivityRow.peerTitle(kind: .received, name: "Sally", serverTitle: "Received") == "Received from Sally")
    }

    @Test("The verb is read from an already-substituted title")
    func substitutedTitle() {
        #expect(ActivityRow.peerTitle(kind: .received, name: "Sally", serverTitle: "Tipped Bob") == "Tip from Sally")
        #expect(ActivityRow.peerTitle(kind: .received, name: "Sally", serverTitle: "Sent to Bob") == "Received from Sally")
    }

    @Test("An unresolved counterparty falls back to the server-rendered title")
    func unresolvedCounterpartyFallsBack() {
        #expect(ActivityRow.peerTitle(kind: .received, name: nil, serverTitle: "Sent") == nil)
        #expect(ActivityRow.peerTitle(kind: .received, name: "", serverTitle: "Sent") == nil)
    }

    @Test("Non-peer activity falls back to the server-rendered title")
    func nonPeerActivityFallsBack() {
        #expect(ActivityRow.peerTitle(kind: .bought, name: "Sally", serverTitle: "Purchased") == nil)
        #expect(ActivityRow.peerTitle(kind: .withdrew, name: "Sally", serverTitle: "Withdrew") == nil)
    }
}
