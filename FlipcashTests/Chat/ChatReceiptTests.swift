//
//  ChatReceiptTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashCore

@Suite("ChatReceipt")
struct ChatReceiptTests {

    @Test("Delivered is status only")
    func deliveredIsStatusOnly() {
        #expect(ChatReceipt.delivered.status == "Delivered")
        #expect(ChatReceipt.delivered.time == nil)
        #expect(ChatReceipt.delivered.displayText == "Delivered")
    }

    @Test("Read splits its status from its time")
    func readSplitsStatusAndTime() {
        let receipt = ChatReceipt.read(time: "3:42 PM")
        // The halves are set in different weights, so the view needs them apart.
        #expect(receipt.status == "Read")
        #expect(receipt.time == "3:42 PM")
        #expect(receipt.displayText == "Read 3:42 PM")
    }

    @Test("Read without a timestamp is status only")
    func readWithoutTimeIsStatusOnly() {
        let receipt = ChatReceipt.read(time: nil)
        #expect(receipt.time == nil)
        #expect(receipt.displayText == "Read")
    }

    @Test("Failed carries its own copy")
    func failedCarriesItsOwnCopy() {
        let receipt = ChatReceipt.failed("Not Delivered. Tap to retry")
        #expect(receipt.status == "Not Delivered. Tap to retry")
        #expect(receipt.displayText == "Not Delivered. Tap to retry")
    }

    @Test("Only the failed case reports failure")
    func onlyFailedReportsFailure() {
        #expect(ChatReceipt.delivered.isFailed == false)
        #expect(ChatReceipt.read(time: "3:42 PM").isFailed == false)
        #expect(ChatReceipt.failed("nope").isFailed == true)
    }

    @Test("Delivered and Read are distinct states")
    func deliveredAndReadAreDistinct() {
        // The whole point of the type: the view can only cross-fade between them if the mapping
        // layer keeps the difference.
        #expect(ChatReceipt.delivered != ChatReceipt.read(time: nil))
    }

    @Test("A message's failure follows its receipt")
    func messageFailureFollowsReceipt() {
        #expect(ChatMessage(id: "a", text: "hi", sender: .me).isFailed == false)
        #expect(ChatMessage(id: "a", text: "hi", sender: .me, receipt: .delivered).isFailed == false)
        #expect(ChatMessage(id: "a", text: "hi", sender: .me, receipt: .failed("x")).isFailed == true)
    }
}
