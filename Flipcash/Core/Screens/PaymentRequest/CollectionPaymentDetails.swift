//
//  CollectionPaymentDetails.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// What the pay sheet draws for a collection that conversions fund: the fee line under the amount,
/// and the Payment Details sheet its ⓘ opens.
nonisolated struct CollectionPaymentSheetContent: Equatable, Sendable {

    struct Line: Equatable, Sendable {
        /// The currency's id, its mint in base58.
        let currency: String
        let name: String
        let amount: String
        let sublabels: [String]
    }

    static let title = "Payment Details"
    static let payHeading = "You’ll Pay"
    static let useHeading = "You’ll Use"

    /// The short state's lines when the balances can't cover the payment without adding Dollars:
    /// "You’re $4.00 Short", "Add $5.00 and Pay $10.00", and the Apple Pay minimum.
    struct TopUp: Equatable, Sendable {
        /// What the button adds, in the request currency's micros.
        let micros: Int64
        let shortBy: String
        let button: String
        let footnote: String
    }

    /// "plus ~$0.02 of conversion fees" or "no conversion fees", from the plan after any top-up
    /// (8.2). `nil` when nothing converts.
    let feeLine: String?

    /// The short state, or nil when the balances cover the payment.
    let topUp: TopUp?

    /// The Request screen's button when no balance funds any of the payment, so tapping it adds
    /// money with Apple Pay and pays with no sheet: "Pay $10.00" when the top-up is the amount
    /// (1.1), else "Add $5.00 and Pay $2.00" over the Apple Pay minimum (2.1).
    struct RequestTopUp: Equatable, Sendable {
        /// What the button adds, in the request currency's micros.
        let micros: Int64
        let title: String
        let footnote: String?
    }

    /// Set when the top-up covers the whole payment; nil when a balance funds any of it, and the
    /// sheet opens as before.
    let requestTopUp: RequestTopUp?

    /// The paying currency's id.
    let payingCurrency: String

    /// "You’ll Pay": the paying currency and the amount.
    let pay: Line

    /// "You’ll Use": a line per leg, in the order the display gives.
    let use: [Line]

    /// "Total": the amounts sold, fees included.
    let total: CollectionFundingDisplay.Row

    init(plan: CollectionFundingPlan, display: CollectionFundingDisplay, currency: CurrencyCode) {
        feeLine = display.modalFee
        let topUp = plan.payableWithoutTopUp ? nil : Self.topUp(plan: plan, currency: currency)
        self.topUp = topUp
        requestTopUp = topUp.flatMap { Self.requestTopUp(plan: plan, topUp: $0, currency: currency) }
        payingCurrency = display.payCurrency
        pay = Line(currency: display.payCurrency, name: display.pay.label, amount: display.pay.amount, sublabels: [])
        use = zip(display.useCurrencies, display.use).map { currency, row in
            Line(currency: currency, name: row.label, amount: row.amount, sublabels: row.sublabels)
        }
        total = display.total
    }

    /// The strings `CollectionFundingDisplay` gives in English, built from its amounts so each
    /// sentence localizes whole. The shortfall rounds up to the minor unit.
    private static func topUp(plan: CollectionFundingPlan, currency: CurrencyCode) -> TopUp {
        let unit = Int64(pow(10.0, Double(6 - currency.maximumFractionDigits)))
        let shortfall = (plan.shortfallMicros + unit - 1) / unit * unit
        let short = CollectionFundingDisplay.amountText(micros: shortfall, currency: currency)
        let added = CollectionFundingDisplay.amountText(micros: plan.topUpMicros, currency: currency)
        let paid = CollectionFundingDisplay.amountText(micros: plan.amountMicros, currency: currency)
        return TopUp(
            micros: plan.topUpMicros,
            shortBy: String(localized: "You’re \(short) Short", comment: "Pay sheet: how much the viewer's balances fall short of a payment"),
            button: String(localized: "Add \(added) and Pay \(paid)", comment: "Pay sheet button: add money with Apple Pay, then pay the request"),
            footnote: String(localized: "The minimum you can add with Apple Pay is $5.", comment: "Pay sheet footnote under the add-and-pay button")
        )
    }

    /// The Request screen's button, when no leg takes anything from a balance. The planner has
    /// already dropped balances under the dust floor, so a dust balance doesn't count.
    private static func requestTopUp(plan: CollectionFundingPlan, topUp: TopUp, currency: CurrencyCode) -> RequestTopUp? {
        let usesNoBalance = plan.legs.allSatisfy { leg in
            leg.dollarsSplit.map { $0.fromBalanceMicros == 0 } ?? (leg.soldMicros == 0)
        }
        guard plan.topUpMicros > 0, usesNoBalance else { return nil }
        guard plan.topUpMicros > plan.amountMicros else {
            let paid = CollectionFundingDisplay.amountText(micros: plan.amountMicros, currency: currency)
            return RequestTopUp(
                micros: plan.topUpMicros,
                title: String(localized: "Pay \(paid)", comment: "Request screen button: add the amount with Apple Pay and pay the request"),
                footnote: nil
            )
        }
        return RequestTopUp(micros: plan.topUpMicros, title: topUp.button, footnote: topUp.footnote)
    }
}

/// The modal's fee line with its info affordance, which opens Payment Details.
struct CollectionPaymentFeeLine: View {

    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(text)
                Image.system(.info)
            }
            .font(.appTextCaption)
            .foregroundStyle(Color.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(text), Payment Details")
    }
}

/// Payment Details (frames 5.3, 6.5, 9.3): what the payment pays and what it sells to get there.
struct CollectionPaymentDetailsView: View {

    let content: CollectionPaymentSheetContent
    /// The icon for a currency id, when the wallet has one.
    let imageURL: (String) -> URL?
    let onBack: () -> Void

    @State private var linesHeight: CGFloat = 0

    /// The tallest the list grows before it scrolls. `PartialSheet` proposes its current height,
    /// which is the pay modal's when this replaces it, so the list sizes itself rather than
    /// filling that proposal.
    private var maxListHeight: CGFloat {
        UIScreen.main.bounds.height * 0.65
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textMain)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Text(CollectionPaymentSheetContent.title)
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)
            }

            // Short lists (5.3, 6.5) fit; a long one (9.3) grows the sheet to the cap and scrolls.
            ScrollView {
                lines
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { linesHeight = $0 }
            }
            .frame(height: min(linesHeight, maxListHeight))
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
    }

    private static let iconSize: CGFloat = 24
    private static let iconSpacing: CGFloat = 8

    private var lines: some View {
        VStack(alignment: .leading, spacing: 20) {
            section(CollectionPaymentSheetContent.payHeading, lines: [content.pay])
            section(CollectionPaymentSheetContent.useHeading, lines: content.use)

            // The divider and "Total" start where the names do (5.3, 9.3), past the icons.
            VStack(alignment: .leading, spacing: 20) {
                Rectangle()
                    .fill(Color.rowSeparator)
                    .frame(height: 1)

                HStack {
                    Text(content.total.label)
                    Spacer()
                    Text(content.total.amount)
                }
                .font(.appTextSmall)
                .foregroundStyle(Color.textMain)
            }
            .padding(.leading, Self.iconSize + Self.iconSpacing)
        }
    }

    private func section(_ heading: String, lines: [CollectionPaymentSheetContent.Line]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(heading)
                .font(.appTextSmall)
                .foregroundStyle(Color.textMain)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                row(line)
            }
        }
    }

    private func row(_ line: CollectionPaymentSheetContent.Line) -> some View {
        HStack(alignment: .top, spacing: Self.iconSpacing) {
            TokenIcon(url: imageURL(line.currency), monogramID: line.currency, size: Self.iconSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(line.name)
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textMain)
                    .frame(minHeight: 24)
                ForEach(line.sublabels, id: \.self) { sublabel in
                    Text(sublabel)
                        .font(.appTextCaption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Spacer()
            Text(line.amount)
                .font(.appTextSmall)
                .foregroundStyle(Color.textMain)
                .frame(minHeight: 24)
        }
    }
}
