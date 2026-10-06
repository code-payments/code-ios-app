//
//  PostPaymentChatTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("PostPaymentChat")
struct PostPaymentChatTests {

    private let dmID = ConversationID(data: Data(repeating: 7, count: 32))

    @Test("A record that landed before the sheet dismissed is pushed at dismissal")
    func recordFirst_pushesAtDismissal() {
        var state = PostPaymentChat()
        state.paymentSucceeded()
        #expect(state.sheetDismissed(dmID: dmID, isScreenInFront: true) == dmID)
        #expect(!state.isAwaitingChat)
    }

    @Test("A record that lands after dismissal is pushed on arrival, once")
    func dismissalFirst_pushesOnArrival() {
        var state = PostPaymentChat()
        state.paymentSucceeded()
        #expect(state.sheetDismissed(dmID: nil, isScreenInFront: true) == nil)
        #expect(state.isAwaitingChat)
        #expect(state.dmArrived(dmID, isScreenInFront: true) == dmID)
        #expect(state.dmArrived(dmID, isScreenInFront: true) == nil)
    }

    @Test("Dismissing without a payment pushes nothing and waits for nothing")
    func noPayment_nothing() {
        var state = PostPaymentChat()
        #expect(state.sheetDismissed(dmID: dmID, isScreenInFront: true) == nil)
        #expect(!state.isAwaitingChat)
    }

    @Test("A late success after an early dismissal doesn't leak into the next dismissal")
    func lateSuccess_doesNotLeak() {
        var state = PostPaymentChat()
        #expect(state.sheetDismissed(dmID: nil, isScreenInFront: true) == nil)
        state.paymentSucceeded()
        #expect(state.sheetDismissed(dmID: dmID, isScreenInFront: true) == dmID)
        #expect(state.sheetDismissed(dmID: dmID, isScreenInFront: true) == nil)
    }

    @Test("A screen no longer in front drops the push at dismissal")
    func notInFront_atDismissal_drops() {
        var state = PostPaymentChat()
        state.paymentSucceeded()
        #expect(state.sheetDismissed(dmID: dmID, isScreenInFront: false) == nil)
        #expect(!state.isAwaitingChat)
    }

    @Test("A screen no longer in front drops the push on arrival")
    func notInFront_onArrival_drops() {
        var state = PostPaymentChat()
        state.paymentSucceeded()
        _ = state.sheetDismissed(dmID: nil, isScreenInFront: true)
        #expect(state.dmArrived(dmID, isScreenInFront: false) == nil)
        #expect(!state.isAwaitingChat)
    }

    @Test("Giving up stops the wait")
    func gaveUp_stopsWaiting() {
        var state = PostPaymentChat()
        state.paymentSucceeded()
        _ = state.sheetDismissed(dmID: nil, isScreenInFront: true)
        state.gaveUp()
        #expect(state.dmArrived(dmID, isScreenInFront: true) == nil)
    }
}
