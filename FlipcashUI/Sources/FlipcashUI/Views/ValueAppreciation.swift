//
//  ValueAppreciation.swift
//  FlipcashUI
//
//  Created by Raul Riera on 2026-01-28.
//

import SwiftUI
import FlipcashCore

public struct ValueAppreciation: View {

    /// Visual treatment. `classic` is the v1 green/red sentiment chip used by the
    /// legacy balance and currency-info screens; `pill` is the v2 neutral bordered
    /// pill (Figma 8966:1583) used only by the new Wallet UI.
    public enum Style {
        case classic
        case pill
    }

    public let amount: FiatAmount
    public let isPositive: Bool
    public let style: Style
    private let isNegligible: Bool
    private var prefix: String {
        guard !isNegligible else { return "" }
        return isPositive ? "+" : "-"
    }

    public init(amount: FiatAmount, isPositive: Bool, style: Style = .classic) {
        self.amount = amount
        self.style = style
        self.isNegligible = amount.value < 0.01
        // Amounts smaller than one cent (e.g. 0.001) are treated as positive
        // to avoid displaying negligible negative rounding artifacts.
        if isNegligible {
            self.isPositive = true
        } else {
            self.isPositive = isPositive
        }
    }

    public var body: some View {
        switch style {
        case .classic:
            classicBody
        case .pill:
            pillBody
        }
    }

    private var classicBody: some View {
        let color = isPositive ? Color.Sentiment.positive : Color.Sentiment.negative

        return HStack {
            Text("\(prefix)\(amount.formatted())")
                .foregroundStyle(color)
                .padding(4)
                .background {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .opacity(0.2)
                }

            Group {
                if isPositive {
                    Text("from currency appreciation")
                } else {
                    Text("from currency depreciation")
                }
            }
                .foregroundStyle(Color.textSecondary)
        }
            .font(.appTextSmall)
            .padding(.bottom, 30)
    }

    // v2 (Figma 8966:1583): a neutral bordered pill — no green/red fill — with the
    // signed delta and a short label, both in secondary text. The (i) info icon in
    // the design is intentionally omitted for now.
    private var pillBody: some View {
        HStack(spacing: 4) {
            Text("\(prefix)\(amount.formatted())")
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                }

            Text(isPositive ? "from appreciation" : "from depreciation")
        }
            .font(.appTextSmall)
            .foregroundStyle(Color.textSecondary)
            .padding(.bottom, 30)
    }
}
