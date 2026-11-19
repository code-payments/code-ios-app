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

    /// "plus ~$0.02 of conversion fees" or "no conversion fees". `nil` when nothing converts, and
    /// when the balances can't cover the payment, which shows today's short state instead.
    let feeLine: String?

    /// The paying currency's id.
    let payingCurrency: String

    /// "You’ll Pay": the paying currency and the amount.
    let pay: Line

    /// "You’ll Use": a line per leg, in the order the display gives.
    let use: [Line]

    /// "Total": the amounts sold, fees included.
    let total: CollectionFundingDisplay.Row

    init(plan: CollectionFundingPlan, display: CollectionFundingDisplay) {
        feeLine = plan.payableWithoutTopUp ? display.modalFee : nil
        payingCurrency = display.payCurrency
        pay = Line(currency: display.payCurrency, name: display.pay.label, amount: display.pay.amount, sublabels: [])
        use = zip(display.useCurrencies, display.use).map { currency, row in
            Line(currency: currency, name: row.label, amount: row.amount, sublabels: row.sublabels)
        }
        total = display.total
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
        }
    }

    private var lines: some View {
        VStack(alignment: .leading, spacing: 20) {
            section(CollectionPaymentSheetContent.payHeading, lines: [content.pay])
            section(CollectionPaymentSheetContent.useHeading, lines: content.use)

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
        HStack(alignment: .top, spacing: 8) {
            TokenIcon(url: imageURL(line.currency), monogramID: line.currency, size: 24)
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
