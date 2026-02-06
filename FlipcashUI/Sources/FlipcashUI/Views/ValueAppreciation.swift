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
    
    public init(amount: Quarks, isPositive: Bool) {
        self.amount = amount
        self.isPositive = isPositive
    }
    
    public var body: some View {
        let prefix = isPositive ? "+" : "-"
        
        HStack {
            Text("\(prefix)\(amount.formatted())")
                .padding(4)
                .background {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isPositive ? Color.Sentiment.positive : Color.Sentiment.negative)
                        .opacity(0.2)
                }
            if isPositive {
                Text("from currency appreciation")
            } else {
                Text("from currency depreciation")
            }
        }
            .font(.appTextSmall)
            .foregroundStyle(isPositive ? Color.Sentiment.positive : Color.Sentiment.negative)
            .padding(.bottom, 30)
    }
}
