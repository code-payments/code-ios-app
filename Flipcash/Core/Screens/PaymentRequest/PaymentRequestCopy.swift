//
//  PaymentRequestCopy.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

/// The words a payment request is shown with, its amounts restated in the viewer's display currency.
struct PaymentRequestCopy {

    let displayCurrency: CurrencyCode
    let rates: [CurrencyCode: Rate]

    init(displayCurrency: CurrencyCode, rates: [CurrencyCode: Rate]) {
        self.displayCurrency = displayCurrency
        self.rates = rates
    }

    init(_ display: DisplayCurrency) {
        self.init(displayCurrency: display.currency, rates: display.rates)
    }

    /// `native` in `currency`, restated for the viewer; the amount as it is when no rate converts it.
    func viewerAmount(_ native: Decimal, currency: String) -> FiatAmount? {
        guard let code = try? CurrencyCode(currencyCode: currency) else { return nil }
        let amount = FiatAmount(value: native, currency: code)
        return amount.converted(to: displayCurrency, rates: rates) ?? amount
    }

    /// A whole amount without its fraction: "$20", "$2.50".
    private func short(_ native: Decimal, currency: String) -> String {
        viewerAmount(native, currency: currency)?.formattedDroppingZeroFraction() ?? ""
    }

    /// "$20 paid, $520 requested".
    func progressLine(_ request: GroupPaymentRequest) -> String {
        let currency = request.split?.currency ?? ""
        return "\(short(request.paidNative, currency: currency)) paid, \(short(request.requestedNative, currency: currency)) requested"
    }

    /// The deck's amount line: "$180 of $520".
    func deckAmounts(_ request: GroupPaymentRequest) -> String {
        let currency = request.split?.currency ?? ""
        return "\(short(request.paidNative, currency: currency)) of \(short(request.requestedNative, currency: currency))"
    }

    /// A history row's amount line: "✓ $520 paid" once COMPLETED, otherwise the progress line.
    func historyAmounts(_ request: GroupPaymentRequest) -> String {
        switch request.status {
        case .completed:
            return "✓ \(short(request.requestedNative, currency: request.split?.currency ?? "")) paid"
        case .open, .closed, .expired, .unknown:
            return progressLine(request)
        }
    }

    /// One share's amount at full precision: "$20.00".
    func shareAmount(_ share: GroupPaymentRequest.Share, of request: GroupPaymentRequest) -> FiatAmount? {
        viewerAmount(Decimal(share.nativeAmount), currency: request.split?.currency ?? "")
    }

    /// A share's amount as a details row and the Send button show it: "$20".
    func shareText(_ share: GroupPaymentRequest.Share, of request: GroupPaymentRequest) -> String {
        short(Decimal(share.nativeAmount), currency: request.split?.currency ?? "")
    }

    /// The per-person amount of a request, taken from its first share.
    func perPersonAmount(_ request: GroupPaymentRequest) -> FiatAmount? {
        guard let share = request.split?.shares.first else { return nil }
        return shareAmount(share, of: request)
    }

    // MARK: - Static copy -

    /// The status line shared by the card, the deck and Request details.
    static func statusLine(_ deadline: GroupPaymentRequest.Deadline) -> String {
        switch deadline {
        case .daysLeft(let days):
            return days == 1 ? "1 day left to pay" : "\(days) days left to pay"
        case .hoursLeft(let hours):
            return hours == 1 ? "1 hour left to pay" : "\(hours) hours left to pay"
        case .minutesLeft(let minutes):
            return minutes == 1 ? "1 minute left to pay" : "\(minutes) minutes left to pay"
        case .paidInFull:
            return "Paid in full"
        case .closed:
            return "Closed"
        case .expired:
            return "Expired"
        }
    }

    /// The status line without "to pay", as the owed strip shows it: "2 days left".
    static func timeLeft(_ deadline: GroupPaymentRequest.Deadline) -> String {
        switch deadline {
        case .daysLeft(let days):
            return days == 1 ? "1 day left" : "\(days) days left"
        case .hoursLeft(let hours):
            return hours == 1 ? "1 hour left" : "\(hours) hours left"
        case .minutesLeft(let minutes):
            return minutes == 1 ? "1 minute left" : "\(minutes) minutes left"
        case .paidInFull, .closed, .expired:
            return statusLine(deadline)
        }
    }

    /// A share row's status: "✓ Paid", or "Hasn't paid yet" / "Didn't pay" depending on whether the
    /// request is still open.
    static func shareStatus(_ share: GroupPaymentRequest.Share, requestIsOpen: Bool) -> String {
        if share.isPaid { return "✓ Paid" }
        return requestIsOpen ? "Hasn't paid yet" : "Didn't pay"
    }

    /// The deck's VoiceOver label: "<N> requests, <title>, <viewer status>, <paid> of <requested> paid, <status>".
    func deckAccessibilityLabel(front: GroupPaymentRequest, title: String, viewerStatus: PaymentRequestViewerStatus, count: Int, now: Date) -> String {
        let parts = [title, viewerStatus.accessibilityText, "\(deckAmounts(front)) paid", Self.statusLine(front.deadline(at: now))]
        let summary = parts.compactMap { $0 }.joined(separator: ", ")
        return count > 1 ? "\(count) requests, \(summary)" : summary
    }

    /// The owed strip's VoiceOver label: "<N> requests, You owe <share> for <title>, <status>".
    static func owedAccessibilityLabel(share: String, title: String, deadline: GroupPaymentRequest.Deadline, count: Int) -> String {
        let summary = "You owe \(share) for \(title), \(statusLine(deadline))"
        return count > 1 ? "\(count) requests, \(summary)" : summary
    }
}
