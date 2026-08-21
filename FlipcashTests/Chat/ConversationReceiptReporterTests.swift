//
//  ConversationReceiptReporterTests.swift
//  FlipcashTests
//

import Testing
import Foundation
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("ConversationReceiptReporter")
struct ConversationReceiptReporterTests {

    private let me: UserID = UUID()
    private let them: UserID = UUID()

    // MARK: - Fixtures -

    private func exchangedFiat(_ value: Decimal, _ currency: CurrencyCode, fx: Decimal = 1) -> ExchangedFiat {
        ExchangedFiat(
            onChainAmount: TokenAmount(quarks: 1_000_000, mint: .usdf),
            nativeAmount: FiatAmount(value: value, currency: currency),
            currencyRate: Rate(fx: fx, currency: currency)
        )
    }

    private func text(id: UInt64, from sender: UserID?) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id),
            senderID: sender,
            content: .text("hi"),
            date: Date(timeIntervalSince1970: TimeInterval(id)),
            unreadSeq: id
        )
    }

    private func tip(id: UInt64, from sender: UserID?, _ value: Decimal = 5, _ currency: CurrencyCode = .usd, fx: Decimal = 1) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id),
            senderID: sender,
            content: .cash(exchangedFiat(value, currency, fx: fx)),
            cashAction: .tipped,
            date: Date(timeIntervalSince1970: TimeInterval(id)),
            unreadSeq: id
        )
    }

    private func cash(id: UInt64, from sender: UserID?) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id),
            senderID: sender,
            content: .cash(exchangedFiat(5, .usd)),
            cashAction: .sent,
            date: Date(timeIntervalSince1970: TimeInterval(id)),
            unreadSeq: id
        )
    }

    // MARK: - Counters (instrument A) -

    @Test("An inbound text counts as one message and no tip")
    func inboundTextCountsAsMessage() {
        let spy = ReceiptSpy()
        let reporter = spy.makeReporter(selfUserID: me)

        reporter.countReceived([text(id: 1, from: them)], countedThrough: nil, delivery: .live)

        #expect(spy.count(of: .messages) == 1)
        #expect(spy.count(of: .tips) == 0)
        #expect(spy.count(of: .tipsValue) == 0)
    }

    @Test("An inbound tip counts as both a tip and a message")
    func inboundTipCountsBoth() {
        let spy = ReceiptSpy()
        let reporter = spy.makeReporter(selfUserID: me)

        reporter.countReceived([tip(id: 1, from: them, 5)], countedThrough: nil, delivery: .live)

        #expect(spy.count(of: .messages) == 1)
        #expect(spy.count(of: .tips) == 1)
        #expect(spy.amount(for: .tipsValue) == 5)
    }

    @Test("A non-tip cash message is a message, not a tip")
    func inboundCashIsNotATip() {
        let spy = ReceiptSpy()
        let reporter = spy.makeReporter(selfUserID: me)

        reporter.countReceived([cash(id: 1, from: them)], countedThrough: nil, delivery: .live)

        #expect(spy.count(of: .messages) == 1)
        #expect(spy.count(of: .tips) == 0)
    }

    @Test("Own messages are never counted")
    func outboundIsNotCounted() {
        let spy = ReceiptSpy()
        let reporter = spy.makeReporter(selfUserID: me)

        reporter.countReceived([text(id: 1, from: me), tip(id: 2, from: me)], countedThrough: nil, delivery: .live)

        #expect(spy.counters.isEmpty)
    }

    @Test("Messages at or below the watermark are not re-counted")
    func watermarkSuppressesReplay() {
        let spy = ReceiptSpy()
        let reporter = spy.makeReporter(selfUserID: me)

        reporter.countReceived(
            [text(id: 1, from: them), text(id: 2, from: them), text(id: 3, from: them)],
            countedThrough: MessageID(value: 2),
            delivery: .live
        )

        #expect(spy.count(of: .messages) == 1)
    }

    @Test("A cold catch-up seeds without counting")
    func coldCatchUpDoesNotCount() {
        let spy = ReceiptSpy()
        let reporter = spy.makeReporter(selfUserID: me)

        reporter.countReceived([text(id: 1, from: them), tip(id: 2, from: them)], countedThrough: nil, delivery: .catchUp)

        #expect(spy.counters.isEmpty)
    }

    @Test("A live delivery into an empty conversation still counts")
    func liveDeliveryWithNoWatermarkCounts() {
        let spy = ReceiptSpy()
        let reporter = spy.makeReporter(selfUserID: me)

        reporter.countReceived([tip(id: 1, from: them, 3)], countedThrough: nil, delivery: .live)

        #expect(spy.count(of: .tips) == 1)
        #expect(spy.amount(for: .tipsValue) == 3)
    }

    @Test("A foreign-currency tip is normalised to USD")
    func foreignTipNormalisesToUSD() {
        let spy = ReceiptSpy()
        spy.rates = [.eur: Rate(fx: 2, currency: .eur)]
        let reporter = spy.makeReporter(selfUserID: me)

        reporter.countReceived([tip(id: 1, from: them, 10, .eur, fx: 2)], countedThrough: nil, delivery: .live)

        #expect(spy.count(of: .tips) == 1)
        #expect(spy.amount(for: .tipsValue) == 5)
    }

    @Test("With no cached rate the tip is counted but its value is skipped")
    func missingRateSkipsValueOnly() {
        let spy = ReceiptSpy()
        let reporter = spy.makeReporter(selfUserID: me)

        reporter.countReceived([tip(id: 1, from: them, 10, .eur, fx: 2)], countedThrough: nil, delivery: .live)

        #expect(spy.count(of: .tips) == 1)
        #expect(spy.count(of: .messages) == 1)
        #expect(spy.count(of: .tipsValue) == 0)
    }

    // MARK: - Events (instrument B) -

    @Test("A crossed inbound tip emits Tip Received only")
    func crossedTipEmitsTipOnly() {
        let spy = ReceiptSpy()
        let reporter = spy.makeReporter(selfUserID: me)

        reporter.reportRead([tip(id: 1, from: them)], chatType: .tipDm)

        #expect(spy.tips.count == 1)
        #expect(spy.tips.first?.chatType == .tipDm)
        #expect(spy.messages.isEmpty)
    }

    @Test("A crossed inbound text emits Message Received")
    func crossedTextEmitsMessage() {
        let spy = ReceiptSpy()
        let reporter = spy.makeReporter(selfUserID: me)

        reporter.reportRead([text(id: 1, from: them)], chatType: .contactDm)

        #expect(spy.messages == [.contactDm])
        #expect(spy.tips.isEmpty)
    }

    @Test("Own crossed messages emit nothing")
    func crossedOwnMessagesEmitNothing() {
        let spy = ReceiptSpy()
        let reporter = spy.makeReporter(selfUserID: me)

        reporter.reportRead([text(id: 1, from: me), tip(id: 2, from: me)], chatType: .tipDm)

        #expect(spy.messages.isEmpty)
        #expect(spy.tips.isEmpty)
    }

    @Test("Every crossed inbound message emits its own event")
    func crossedWindowEmitsOnePerMessage() {
        let spy = ReceiptSpy()
        let reporter = spy.makeReporter(selfUserID: me)

        reporter.reportRead(
            [text(id: 1, from: them), tip(id: 2, from: them), text(id: 3, from: them)],
            chatType: .tipDm
        )

        #expect(spy.messages.count == 2)
        #expect(spy.tips.count == 1)
    }
}
