//
//  ReceiptSpy.swift
//  FlipcashTests
//

import Foundation
import FlipcashCore
@testable import Flipcash

/// Records everything a `ConversationReceiptReporter` would have sent to Mixpanel.
/// The real transport is inert in tests (`Analytics.isEnabled` is false), so the
/// reporter's closures are the only observable seam.
@MainActor
final class ReceiptSpy {

    var counters: [(counter: Analytics.ReceivedCounter, amount: Double)] = []
    var tips: [(chatType: ConversationType?, exchangedFiat: ExchangedFiat)] = []
    var messages: [ConversationType?] = []

    /// Rates the reporter will find when normalising a tip to USD.
    var rates: [CurrencyCode: Rate] = [:]

    func amount(for counter: Analytics.ReceivedCounter) -> Double {
        counters.filter { $0.counter == counter }.reduce(0) { $0 + $1.amount }
    }

    func count(of counter: Analytics.ReceivedCounter) -> Int {
        counters.count { $0.counter == counter }
    }

    func makeReporter(selfUserID: UserID) -> ConversationReceiptReporter {
        let reporter = ConversationReceiptReporter(
            selfUserID: selfUserID,
            increment: { [self] counter, amount in counters.append((counter, amount)) },
            trackTipReceived: { [self] chatType, exchangedFiat in tips.append((chatType, exchangedFiat)) },
            trackMessageReceived: { [self] chatType in messages.append(chatType) }
        )
        reporter.usdRate = { [self] currency in rates[currency] }
        return reporter
    }
}
