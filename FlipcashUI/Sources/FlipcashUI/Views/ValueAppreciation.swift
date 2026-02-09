//
//  ValueAppreciation.swift
//  FlipcashUI
//
//  Created by Raul Riera on 2026-01-28.
//

import SwiftUI
import FlipcashCore

public struct ValueAppreciation: View {
    public let amount: Quarks
    public let isPositive: Bool
    private let isNegligible: Bool
    private var prefix: String {
        guard !isNegligible else { return "" }
        return isPositive ? "+" : "-"
    }
        
    public init(amount: Quarks, isPositive: Bool) {
        self.amount = amount
        self.isNegligible = amount.decimalValue < 0.01
        // Amounts smaller than one cent (e.g. 0.001) are treated as positive
        // to avoid displaying negligible negative rounding artifacts.
        if isNegligible {
            self.isPositive = true
        } else {
            self.isPositive = isPositive
        }
    }
    
    public var body: some View {
        let color = isPositive ? Color.Sentiment.positive : Color.Sentiment.negative
        
        HStack {
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
}
